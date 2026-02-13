import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/services/system_chrome.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

import '../../../core/utils/datetime_utils.dart';
import '../../../core/utils/developer_info_dialog.dart';
import '../../../core/utils/direction_utils.dart';
import '../../../core/utils/focus_point_provider.dart';
import '../../compass/presentation/compass_provider.dart';
import '../../gallery/data/gallery_folder_screen.dart';
import '../../gallery/presentation/gallery_image_viewer.dart';
import '../../gallery/presentation/last_image_provider.dart';
import '../../location/presentation/location_viewmodel.dart';
import '../../overlay/presentation/live_overlay_painter.dart';
import '../../overlay/presentation/overlay_preview_state.dart';
import 'camera_viewmodel.dart';
import 'note_input_sheet.dart';

class CameraScreen extends ConsumerWidget {
  const CameraScreen({super.key});
  DeviceOrientation _toDeviceOrientation(
      NativeDeviceOrientation orientation) {

    switch (orientation) {
      case NativeDeviceOrientation.landscapeLeft:
        return DeviceOrientation.landscapeLeft;

      case NativeDeviceOrientation.landscapeRight:
        return DeviceOrientation.landscapeRight;

      case NativeDeviceOrientation.portraitDown:
        return DeviceOrientation.portraitDown;

      case NativeDeviceOrientation.portraitUp:
      default:
        return DeviceOrientation.portraitUp;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraState = ref.watch(cameraViewModelProvider);
    final cameraVM = ref.read(cameraViewModelProvider.notifier);

    final overlayData = ref.watch(overlayPreviewProvider);
    final lastImage = ref.watch(lastImageProvider);
    final focusPoint = ref.watch(focusPointProvider);


    // ================= LOCATION LISTENER =================
    ref.listen(locationStreamProvider, (_, next) {
      next.when(
        data: (position) {
          final current = ref.read(overlayPreviewProvider);

          // ✅ UPDATE DATA + REMOVE WARNING
          ref.read(overlayPreviewProvider.notifier).state =
              current.copyWith(
                dateTime: DateTimeUtils.formattedNow(),
                latitude: position.latitude,
                longitude: position.longitude,
                altitude: position.altitude,
                locationWarning: null, // IMPORTANT
              );
        },

        loading: () {
          final current = ref.read(overlayPreviewProvider);

          // show loading only if no valid location yet
          if (current.latitude == 0 &&
              current.longitude == 0) {
            ref.read(overlayPreviewProvider.notifier).state =
                current.copyWith(
                  locationWarning: "Fetching location...",
                );
          }
        },

        error: (_, __) {
          final current = ref.read(overlayPreviewProvider);

          // ✅ ONLY show error if location really missing
          if (current.latitude == 0 &&
              current.longitude == 0) {
            ref.read(overlayPreviewProvider.notifier).state =
                current.copyWith(
                  locationWarning: "Location unavailable",
                );
          }
        },
      );
    });

    // ================= COMPASS LISTENER =================
    ref.listen(compassHeadingProvider, (_, next) {
      next.whenData((heading) {
        final current = ref.read(overlayPreviewProvider);

        ref.read(overlayPreviewProvider.notifier).state =
            current.copyWith(
              heading: heading,
              direction: DirectionUtils.toCardinal(heading),
            );
      });
    });

    if (!cameraState.isReady || cameraState.controller == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

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
      
                    return NativeDeviceOrientationReader(
                      useSensor: true,
                      builder: (context) {
      
      
                        final nativeOrientation =
                        NativeDeviceOrientationReader.orientation(context);

                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          cameraVM.updateOrientation(nativeOrientation);
                        });                        return  Stack(
                      children: [
                        // ✅ TAP TO FOCUS AREA
                        GestureDetector(
                          onTapDown: (details) {
                            final tapPosition = details.localPosition;
                      
                            ref
                                .read(focusPointProvider.notifier)
                                .state = tapPosition;
                      
                            cameraVM.setFocusPoint(
                              tapPosition,
                              previewSize,
                            );
                      
                            // auto hide focus box
                            Future.delayed(
                              const Duration(seconds: 1),
                                  () {
                                ref
                                    .read(focusPointProvider.notifier)
                                    .state = null;
                              },
                            );
                          },
                          child: CameraPreview(
                            cameraState.controller!,
                          ),
                        ),
                      
                        // ✅ LIVE OVERLAY
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: LiveOverlayPainter(
                                overlayData,nativeOrientation
      
                              ),
                            ),
                      
                          ),
                        ),
                        // ✅ INFO
                        Positioned(
                          left: 16,
                          child: IconButton(
                            icon: const Icon(Icons.info_outline,
                                color: Colors.white),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => const DeveloperInfoDialog(),
                              );
                            },
                          ),
                        ),
/*
                        Positioned(
                          top: 100,
                          left: 16,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            color: Colors.black54,
                            child: Text(
                              cameraState.controller!
                                  .value.deviceOrientation
                                  .toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
*/

                        // ✅ FOCUS INDICATOR
                        if (focusPoint != null)
                          Positioned(
                            left: focusPoint.dx - 30,
                            top: focusPoint.dy - 30,
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.yellow,
                                  width: 2,
                                ),
                                borderRadius:
                                BorderRadius.circular(8),
                              ),
                            ),
                          ),
                      
                      
                        // ✏️ Edit note button
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
                                isScrollControlled: true,
                                backgroundColor:
                                Colors.transparent,
                                builder: (_) =>
                                const NoteInputSheet(),
                              );
                            },
                          ),
                        ),
                      ],
                                      );},
                    );
                },
              ),
            ),
      
            // ================= BOTTOM BAR =================
            Container(
              height: 140,
              padding:
              const EdgeInsets.symmetric(horizontal: 24),
              color: Colors.black,
              child: Row(
                mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
                children: [
                  // FLASH
                  IconButton(
                    icon: Icon(
                      cameraState.flashOn
                          ? Icons.flash_on
                          : Icons.flash_off,
                      color: Colors.white,
                    ),
                    onPressed: cameraVM.toggleFlash,
                  ),
      
                  // CAPTURE BUTTON
                  GestureDetector(
                    onTap: () => cameraVM.capture(context),
                    child: Container(
                      height: 72,
                      width: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(
                          color: Colors.grey.shade400,
                          width: 4,
                        ),
                      ),
                    ),
                  ),
      
                  // GALLERY
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const GalleryFolderScreen(),
                        ),
                      );
                    },
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.grey.shade800,
                      backgroundImage:
                      lastImage != null ? FileImage(lastImage) : null,
                      child: lastImage == null
                          ? const Icon(Icons.image, color: Colors.white)
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
