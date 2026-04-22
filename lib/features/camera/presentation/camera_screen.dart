import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/utils/datetime_utils.dart';
import '../../../core/utils/developer_info_dialog.dart';
import '../../../core/utils/device_orientation_provider.dart';
import '../../../core/utils/direction_utils.dart';
import '../../../core/utils/focus_point_provider.dart';
import '../../../privacypolicy/privacyProvider.dart';
import '../../compass/presentation/compass_provider.dart';
import '../../gallery/data/gallery_folder_screen.dart';
import '../../gallery/presentation/last_image_provider.dart';
import '../../location/presentation/location_viewmodel.dart';
import '../../overlay/presentation/live_overlay_painter.dart';
import '../../overlay/presentation/overlay_preview_state.dart';
import '../data/CameraState.dart';
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
  Timer? _dateTimer;
  Timer? _focusTimer;
  bool _isCapturing = false;
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
  void initState() {
    super.initState();

    /// DATE TIME UPDATE TIMER
    _dateTimer = Timer.periodic(
      const Duration(seconds: 1),
          (_) {
        final current =
        ref.read(overlayPreviewProvider);

        ref.read(overlayPreviewProvider.notifier).state =
            current.copyWith(
              dateTime: DateTimeUtils.formattedNow(),
            );
      },
    );
  }

  @override
  void dispose() {
    _dateTimer?.cancel();
    _focusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final privacyAccepted = ref.watch(privacyProvider);
    final cameraState = ref.watch(cameraViewModelProvider);
    final cameraVM =
    ref.read(cameraViewModelProvider.notifier);

    final overlayData = ref.watch(overlayPreviewProvider);
    final lastImage = ref.watch(lastImageProvider);
    final focusPoint = ref.watch(focusPointProvider);
    final deviceOrientation =
    ref.watch(deviceOrientationProvider);

    final CameraController? controller =
        cameraState.controller;

    /// ===============================
    /// LISTENERS (CORRECT PLACE)
    /// ===============================

    if (privacyAccepted == true) {
      ref.listen(locationStreamProvider, (_, next) async {
        next.whenData((position) async {
          final current = ref.read(overlayPreviewProvider);

          final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

          final permission =
          await Geolocator.checkPermission();

          if (!serviceEnabled) {
            ref.read(overlayPreviewProvider.notifier).state =
                current.copyWith(
                  latitude: 0,
                  longitude: 0,
                  altitude: 0,
                  locationWarning: "GPS turned off",
                );
            return;
          }

          if (permission == LocationPermission.denied ||
              permission == LocationPermission.deniedForever) {
            ref.read(overlayPreviewProvider.notifier).state =
                current.copyWith(
                  latitude: 0,
                  longitude: 0,
                  altitude: 0,
                  locationWarning: "Give location permission",
                );
            return;
          }

          if (position == null) {
            ref.read(overlayPreviewProvider.notifier).state =
                current.copyWith(
                  latitude: 0,
                  longitude: 0,
                  altitude: 0,
                  locationWarning: "Fetching location...",
                );
            return;
          }

          ref.read(overlayPreviewProvider.notifier).state =
              current.copyWith(
                latitude: position.latitude,
                longitude: position.longitude,
                altitude: position.altitude,
                clearLocationWarning: true,
              );
        });
      });
    }
    ref.listen(compassHeadingProvider, (_, next) {
      next.whenData((heading) {

        final current =
        ref.read(overlayPreviewProvider);

        ref.read(overlayPreviewProvider.notifier).state =
            current.copyWith(
              heading: heading,
              direction: DirectionUtils.toCardinal(heading),
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
                      IgnorePointer(
                        ignoring: _isCapturing,
                        child: Stack(
                          children: [
                            GestureDetector(
                              onTapDown: (details) {
                                if (!cameraState.isReady ||
                                    controller == null ||
                                    !controller.value.isInitialized) {
                                  return;
                                }

                                final tapPosition = details.localPosition;

                                // Cancel existing timer
                                _focusTimer?.cancel();

                                ref.read(focusPointProvider.notifier).state = tapPosition;
                                cameraVM.setFocusPoint(tapPosition, previewSize);

                                setState(() {
                                  _showExposure = true;
                                });

                                // Smart Focus Timeout: Return to continuous focus after 5 seconds
                                _focusTimer = Timer(const Duration(seconds: 5), () {
                                  if (!mounted) return;

                                  // Only reset if we are still in the same focus session
                                  if (ref.read(focusPointProvider) == tapPosition) {
                                    cameraVM.resetFocus();
                                    ref.read(focusPointProvider.notifier).state = null;
                                    setState(() => _showExposure = false);
                                  }
                                });
                              },
                              onScaleUpdate: (details) {
                                if (controller == null || !controller.value.isInitialized) return;

                                // 1. Handle Zoom (Pinch)
                                if (details.scale != 1.0) {
                                  cameraVM.setZoom(cameraState.zoom * details.scale);
                                }
                                // 2. Handle Exposure (Single finger vertical slide)
                                else {
                                  // Sensitivity adjustment: 0.02 seems natural
                                  final delta = -details.focalPointDelta.dy * 0.02;
                                  if (delta != 0) {
                                    cameraVM.changeExposure(delta);

                                    // Ensure exposure UI stays visible while sliding
                                    if (!_showExposure) {
                                      setState(() => _showExposure = true);
                                    }
                                  }
                                }
                              },
                              child: Stack(
                                children: [
                                  if (controller != null &&
                                      controller.value.isInitialized &&
                                      cameraState.isReady)
                                    SizedBox.expand(
                                      child: Center(
                                        child: AspectRatio(
                                          aspectRatio: cameraState.aspectRatio == CameraAspectRatio.ratio4_3 ? 3 / 4 : 9 / 16,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              FittedBox(
                                                fit: BoxFit.cover,
                                                child: SizedBox(
                                                  width: controller.value.previewSize!.height,
                                                  height: controller.value.previewSize!.width,
                                                  child: CameraPreview(controller),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    const SizedBox.expand(
                                      child: ColoredBox(
                                        color: Colors.black,
                                      ),
                                    ),

                                  AnimatedOpacity(
                                    opacity: (cameraState.isReady && controller != null && cameraState.error == null) ? 0 : 1,
                                    duration: const Duration(milliseconds: 250),
                                    child: Container(
                                      color: Colors.black,
                                      child: Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.camera_alt,
                                              color: Colors.white24,
                                              size: 50,
                                            ),
                                            if (cameraState.error != null) ...[
                                              const SizedBox(height: 16),
                                              Text(
                                                "Camera Error: ${cameraState.error}",
                                                style: const TextStyle(color: Colors.white70),
                                                textAlign: TextAlign.center,
                                              ),
                                              TextButton(
                                                onPressed: () => ref.read(cameraViewModelProvider.notifier).initialize(),
                                                child: const Text("Retry"),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      /// OVERLAY
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
                      ///capture flash
                      if (_isCapturing)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: 0.2, // 🔥 subtle professional effect
                              duration: const Duration(milliseconds: 80),
                              child: Container(color: Colors.black),
                            ),
                          ),
                        ),
                      /// FOCUS + EXPOSURE UI
                      if (focusPoint != null)
                        Positioned.fill(
                          child: Stack(
                            children: [
                              Positioned(
                                left: (focusPoint.dx - 35).clamp(8.0, constraints.maxWidth - 120),
                                top: (focusPoint.dy - 35).clamp(8.0, constraints.maxHeight - 200),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 70,
                                          height: 70,
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: Colors.yellow.withValues(alpha: 0.8),
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Center(
                                            child: Container(
                                              width: 5,
                                              height: 5,
                                              decoration: const BoxDecoration(
                                                color: Colors.yellow,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (_showExposure) ...[
                                          const SizedBox(width: 12),
                                          Column(
                                            children: [
                                              const Icon(Icons.wb_sunny, color: Colors.yellow, size: 20),
                                              const SizedBox(height: 8),
                                              Container(
                                                width: 4,
                                                height: 100,
                                                decoration: BoxDecoration(
                                                  color: Colors.white24,
                                                  borderRadius: BorderRadius.circular(2),
                                                ),
                                                child: FractionallySizedBox(
                                                  alignment: Alignment.bottomCenter,
                                                  heightFactor: ((cameraState.exposure - cameraState.minExposure) / (cameraState.maxExposure - cameraState.minExposure)).clamp(0.0, 1.0),
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors.yellow,
                                                      borderRadius: BorderRadius.circular(2),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    GestureDetector(
                                      onTap: () {
                                        _focusTimer?.cancel();
                                        cameraVM.resetFocus();
                                        ref.read(focusPointProvider.notifier).state = null;
                                        setState(() => _showExposure = false);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.filter_center_focus, color: Colors.yellow, size: 14),
                                            SizedBox(width: 4),
                                            Text("AUTO", style: TextStyle(color: Colors.yellow, fontSize: 10, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      /// ORIENTATION LABEL
/*
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
                                .withValues(alpha: 0.6),
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
*/

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
                        left: 16,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                cameraState.aspectRatio == CameraAspectRatio.ratio4_3
                                    ? Icons.crop_3_2
                                    : Icons.crop_16_9,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                final nextRatio = cameraState.aspectRatio == CameraAspectRatio.ratio4_3
                                    ? CameraAspectRatio.ratio16_9
                                    : CameraAspectRatio.ratio4_3;
                                cameraVM.setAspectRatio(nextRatio);
                              },
                            ),
                            Text(
                              cameraState.aspectRatio == CameraAspectRatio.ratio4_3 ? "3:4" : "9:16",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
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
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          cameraState.flashMode == FlashMode.always
                                  ? Icons.flash_on
                                  : Icons.flash_off,
                          color: cameraState.flashMode == FlashMode.off
                              ? Colors.white54
                              : Colors.white,
                        ),
                        onPressed: cameraVM.cycleFlashMode,
                      ),
                      Text(
                        cameraState.flashMode == FlashMode.always ? "ON" : "OFF",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  CaptureButton(
                    onCapture: () async {
                      if (!cameraState.isReady || _isCapturing) return;

                      // 🔥 Start subtle UI feedback
                      setState(() => _isCapturing = true);

                      // 🔊 shutter sound
                      SystemSound.play(SystemSoundType.click);

                      // 📳 haptic (feels premium)
                      HapticFeedback.mediumImpact();

                      try {
                        await cameraVM.capture(context);
                      } catch (e) {
                        debugPrint("Capture error: $e");
                      }

                      // 🔥 very quick reset (no long flash delay)
                      await Future.delayed(const Duration(milliseconds: 80));

                      if (mounted) {
                        setState(() => _isCapturing = false);
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