import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/datetime_utils.dart';
import '../../../core/utils/developer_info_dialog.dart';
import '../../../core/utils/device_orientation_provider.dart';
import '../../../core/utils/direction_utils.dart';
import '../../../core/utils/focus_point_provider.dart';
import '../../compass/presentation/compass_provider.dart';
import '../../gallery/data/gallery_folder_screen.dart';
import '../../gallery/presentation/last_image_provider.dart';
import '../../location/presentation/location_viewmodel.dart';
import '../../overlay/presentation/live_overlay_painter.dart';
import '../../overlay/presentation/overlay_preview_state.dart';
import 'camera_viewmodel.dart';
import 'capture_button.dart';
import 'note_input_sheet.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() =>
      _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> {

  bool _showExposure = false;

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
  Widget build(BuildContext context) {

    final cameraState = ref.watch(cameraViewModelProvider);
    final cameraVM =
    ref.read(cameraViewModelProvider.notifier);

    final overlayData = ref.watch(overlayPreviewProvider);
    final lastImage = ref.watch(lastImageProvider);
    final focusPoint = ref.watch(focusPointProvider);
    final deviceOrientation =
    ref.watch(deviceOrientationProvider);

    /// IMPORTANT: freeze controller reference for this build
    final CameraController? controller =
        cameraState.controller;

    ref.listen(locationStreamProvider, (_, next) {
      next.when(
        data: (position) {
          final current =
          ref.read(overlayPreviewProvider);

          ref.read(overlayPreviewProvider.notifier).state =
              current.copyWith(
                dateTime: DateTimeUtils.formattedNow(),
                latitude: position.latitude,
                longitude: position.longitude,
                altitude: position.altitude,
                locationWarning: null,
              );
        },
        loading: () {},
        error: (_, __) {},
      );
    });

    ref.listen(compassHeadingProvider, (_, next) {
      next.whenData((heading) {
        final current =
        ref.read(overlayPreviewProvider);

        ref.read(overlayPreviewProvider.notifier).state =
            current.copyWith(
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

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {

                  final previewSize = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );

                  return Stack(
                    children: [

                      /// CAMERA PREVIEW
                      GestureDetector(
                        onTapDown: (details) {

                          if (!cameraState.isReady ||
                              controller == null ||
                              !controller.value.isInitialized) {
                            return;
                          }

                          final tapPosition =
                              details.localPosition;

                          ref
                              .read(focusPointProvider.notifier)
                              .state = tapPosition;

                          cameraVM.setFocusPoint(
                              tapPosition, previewSize);

                          setState(() {
                            _showExposure = true;
                          });

                          Future.delayed(
                              const Duration(milliseconds: 1500),
                                  () {
                                if (!mounted) return;
                                ref
                                    .read(focusPointProvider.notifier)
                                    .state = null;

                                setState(() {
                                  _showExposure = false;
                                });
                              });
                        },
                        onPanUpdate: (details) {
                          if (controller == null ||
                              !controller.value.isInitialized) return;

                          final verticalDelta =
                          -details.delta.dy;
                          final horizontalDelta =
                              details.delta.dx;

                          final delta =
                              (verticalDelta + horizontalDelta) *
                                  0.03;

                          cameraVM.changeExposure(delta);
                        },
                        child: Stack(
                          children: [

                            /// FULL SCREEN CAMERA PREVIEW (SAFE)
                            if (controller != null &&
                                controller.value.isInitialized &&
                                cameraState.isReady)
                              LayoutBuilder(
                                builder: (context, constraints) {

                                  final preview =
                                  controller.value.previewSize!;

                                  return ClipRect(
                                    child: OverflowBox(
                                      alignment: Alignment.center,
                                      child: FittedBox(
                                        fit: BoxFit.cover,
                                        child: SizedBox(
                                          width: preview.height,
                                          height: preview.width,
                                          child: CameraPreview(controller),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              )
                            else
                              const SizedBox.expand(
                                child: ColoredBox(
                                  color: Colors.black,
                                ),
                              ),

                            /// LOADING OVERLAY
                            AnimatedOpacity(
                              opacity: (cameraState.isReady &&
                                  controller != null)
                                  ? 0
                                  : 1,
                              duration:
                              const Duration(milliseconds: 250),
                              child: Container(
                                color: Colors.black,
                                child: const Center(
                                  child: Icon(
                                    Icons.camera_alt,
                                    color: Colors.white24,
                                    size: 50,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      /// OVERLAY PAINTER
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: LiveOverlayPainter(
                              overlayData,
                              deviceOrientation,
                            ),
                          ),
                        ),
                      ),

                      /// FOCUS + EXPOSURE UI
                      if (focusPoint != null)
                        Positioned.fill(
                          child: Stack(
                            children: [
                              Positioned(
                                left: (focusPoint.dx - 30)
                                    .clamp(
                                    8.0,
                                    MediaQuery.of(context)
                                        .size
                                        .width -
                                        120),
                                top: (focusPoint.dy - 30)
                                    .clamp(
                                    8.0,
                                    MediaQuery.of(context)
                                        .size
                                        .height -
                                        200),
                                child: Row(
                                  children: [
                                    Container(
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

                                    if (_showExposure)
                                      const SizedBox(width: 8),

                                    if (_showExposure)
                                      Column(
                                        children: [
                                          const Icon(
                                            Icons.wb_sunny,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            cameraVM.exposureValue
                                                .toStringAsFixed(1),
                                            style:
                                            const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            width: 3,
                                            height: 80,
                                            decoration:
                                            BoxDecoration(
                                              color: Colors.white24,
                                              borderRadius:
                                              BorderRadius.circular(2),
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                      /// ORIENTATION LABEL
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
                            BorderRadius.circular(8),
                          ),
                          child: Text(
                            _orientationText(
                                deviceOrientation),
                            style: const TextStyle(
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
                            color: Colors.amberAccent,
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
                  );
                },
              ),
            ),

            /// BOTTOM CONTROLS
            Container(
              height: 140,
              padding:
              const EdgeInsets.symmetric(horizontal: 24),
              color: Colors.black,
              child: Row(
                mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(
                      cameraState.flashOn
                          ? Icons.flash_on
                          : Icons.flash_off,
                      color: Colors.white,
                    ),
                    onPressed: cameraVM.toggleFlash,
                  ),
                  CaptureButton(
                    onCapture: () {
                      if (cameraState.isReady) {
                        cameraVM.capture(context);
                      }
                    },
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
                      backgroundImage: lastImage != null
                          ? FileImage(lastImage)
                          : null,
                      child: lastImage == null
                          ? const Icon(Icons.image,
                          color: Colors.white)
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
