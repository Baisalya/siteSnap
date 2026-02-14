import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/utils/datetime_utils.dart';
import '../../../core/utils/developer_info_dialog.dart';
import '../../../core/utils/direction_utils.dart';
import '../../../core/utils/focus_point_provider.dart';
import '../../compass/presentation/compass_provider.dart';
import '../../gallery/data/gallery_folder_screen.dart';
import '../../gallery/presentation/last_image_provider.dart';
import '../../location/presentation/location_viewmodel.dart';
import '../../overlay/presentation/live_overlay_painter.dart';
import '../../overlay/presentation/overlay_preview_state.dart';
import 'camera_viewmodel.dart';
import 'note_input_sheet.dart';

final deviceOrientationProvider =
StateProvider<DeviceOrientation>(
        (ref) => DeviceOrientation.portraitUp);

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() =>
      _CameraScreenState();
}

class _CameraScreenState
    extends ConsumerState<CameraScreen> {

  StreamSubscription? _sensorSub;

  @override
  void initState() {
    super.initState();

    _sensorSub = accelerometerEvents.listen((event) {
      final x = event.x;
      final y = event.y;

      DeviceOrientation orientation;

      // prevents jumping when device slightly tilted
      const threshold = 6.0;

      if (x.abs() > y.abs()) {
        // LANDSCAPE
        if (x > threshold) {
          orientation = DeviceOrientation.landscapeRight;
        } else if (x < -threshold) {
          orientation = DeviceOrientation.landscapeLeft;
        } else {
          return;
        }
      } else {
        // PORTRAIT
        if (y > threshold) {
          orientation = DeviceOrientation.portraitUp;
        } else if (y < -threshold) {
          orientation = DeviceOrientation.portraitDown;
        } else {
          return;
        }
      }

      ref.read(deviceOrientationProvider.notifier).state =
          orientation;
    });
  }

  String _orientationText(DeviceOrientation orientation) {
    switch (orientation) {
      case DeviceOrientation.portraitUp:
        return "Portrait Up";
      case DeviceOrientation.portraitDown:
        return "Portrait Down";
      case DeviceOrientation.landscapeLeft:
        return "Landscape Left";
      case DeviceOrientation.landscapeRight:
        return "Landscape Right";
    }
  }

  @override
  void dispose() {
    _sensorSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cameraState = ref.watch(cameraViewModelProvider);
    final cameraVM =
    ref.read(cameraViewModelProvider.notifier);

    final overlayData = ref.watch(overlayPreviewProvider);
    final lastImage = ref.watch(lastImageProvider);
    final focusPoint = ref.watch(focusPointProvider);
    final deviceOrientation =
    ref.watch(deviceOrientationProvider);
    // ================= LOCATION LISTENER =================

    ref.listen(locationStreamProvider, (_, next) {
      next.when(
        data: (position) {
          final current =
          ref.read(overlayPreviewProvider);
          // ✅ UPDATE DATA + REMOVE WARNING

          ref
              .read(overlayPreviewProvider.notifier)
              .state = current.copyWith(
            dateTime: DateTimeUtils.formattedNow(),
            latitude: position.latitude,
            longitude: position.longitude,
            altitude: position.altitude,
            locationWarning: null,
          );
        },
        loading: () {
          final current =
          ref.read(overlayPreviewProvider);

          if (current.latitude == 0 &&
              current.longitude == 0) {
            ref
                .read(overlayPreviewProvider.notifier)
                .state = current.copyWith(
              locationWarning: "Fetching location...",
            );
          }
        },
        error: (_, __) {
          final current =
          ref.read(overlayPreviewProvider);
          // ✅ ONLY show error if location really missing

          if (current.latitude == 0 &&
              current.longitude == 0) {
            ref
                .read(overlayPreviewProvider.notifier)
                .state = current.copyWith(
              locationWarning: "Location unavailable",
            );
          }
        },
      );
    });

    ref.listen(compassHeadingProvider, (_, next) {
      next.whenData((heading) {
        final current =
        ref.read(overlayPreviewProvider);

        ref
            .read(overlayPreviewProvider.notifier)
            .state = current.copyWith(
          heading: heading,
          direction:
          DirectionUtils.toCardinal(heading),
        );
      });
    });
    ref.listen<DeviceOrientation>(
      deviceOrientationProvider,
          (_, next) {
        cameraVM.updateOrientation(next);
      },
    );
    if (!cameraState.isReady ||
        cameraState.controller == null) {
      return const Scaffold(
        body:
        Center(child: CircularProgressIndicator()),
      );
    }

    final controller = cameraState.controller!;

 /*   WidgetsBinding.instance.addPostFrameCallback((_) {
      cameraVM.updateOrientation(deviceOrientation);
    });*/

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            // ================= CAMERA PREVIEW =================
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final previewSize = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );

                  return Stack(
                    children: [
                      GestureDetector(
                        onTapDown: (details) {
                          final tapPosition =
                              details.localPosition;

                          ref
                              .read(
                              focusPointProvider
                                  .notifier)
                              .state = tapPosition;

                          cameraVM.setFocusPoint(
                            tapPosition,
                            previewSize,
                          );

                          Future.delayed(
                            const Duration(seconds: 1),
                                () {
                              ref
                                  .read(
                                  focusPointProvider
                                      .notifier)
                                  .state = null;
                            },
                          );
                        },
                        child:
                        CameraPreview(controller),
                      ),

                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter:
                            LiveOverlayPainter(
                              overlayData,
                              deviceOrientation,
                            ),
                          ),
                        ),
                      ),

                      // ORIENTATION TEXT
                      Positioned(
                        bottom: 20,
                        left: 16,
                        child: Container(
                          padding:
                          const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black
                                .withOpacity(0.6),
                            borderRadius:
                            BorderRadius.circular(
                                8),
                          ),
                          child: Text(
                            _orientationText(
                                deviceOrientation),
                            style:
                            const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight:
                              FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      Positioned(
                        left: 16,
                        child: IconButton(
                          icon: const Icon(
                            Icons.info_outline,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (_) =>
                              const DeveloperInfoDialog(),
                            );
                          },
                        ),
                      ),

                      if (focusPoint != null)
                        Positioned(
                          left:
                          focusPoint.dx - 30,
                          top:
                          focusPoint.dy - 30,
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration:
                            BoxDecoration(
                              border: Border.all(
                                color:
                                Colors.yellow,
                                width: 2,
                              ),
                              borderRadius:
                              BorderRadius
                                  .circular(
                                  8),
                            ),
                          ),
                        ),

                      Positioned(
                        right: 16,
                        child: IconButton(
                          icon: const Icon(
                            Icons.edit,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled:
                              true,
                              backgroundColor:
                              Colors
                                  .transparent,
                              builder: (_) =>
                              const NoteInputSheet(),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // BOTTOM CONTROLS
            Container(
              height: 140,
              padding:
              const EdgeInsets.symmetric(
                  horizontal: 24),
              color: Colors.black,
              child: Row(
                mainAxisAlignment:
                MainAxisAlignment
                    .spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(
                      cameraState.flashOn
                          ? Icons.flash_on
                          : Icons.flash_off,
                      color: Colors.white,
                    ),
                    onPressed:
                    cameraVM.toggleFlash,
                  ),
                  GestureDetector(
                    onTap: () =>
                        cameraVM.capture(context),
                    child: Container(
                      height: 72,
                      width: 72,
                      decoration:
                      BoxDecoration(
                        shape:
                        BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(
                          color:
                          Colors.grey.shade400,
                          width: 4,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                          const GalleryFolderScreen(),
                        ),
                      );
                    },
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor:
                      Colors.grey.shade800,
                      backgroundImage:
                      lastImage != null
                          ? FileImage(
                          lastImage)
                          : null,
                      child: lastImage ==
                          null
                          ? const Icon(
                          Icons.image,
                          color:
                          Colors.white)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
