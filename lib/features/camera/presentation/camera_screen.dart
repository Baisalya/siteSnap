import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:surveycam/core/services/location_service.dart';
import 'package:surveycam/core/services/weather_service.dart';
import 'package:surveycam/core/utils/datetime_utils.dart';
import 'package:surveycam/core/utils/developer_info_dialog.dart';
import 'package:surveycam/core/utils/device_orientation_provider.dart';
import 'package:surveycam/core/utils/direction_utils.dart';
import 'package:surveycam/core/utils/focus_point_provider.dart';
import 'package:surveycam/features/compass/presentation/compass_provider.dart';
import 'package:surveycam/features/gallery/data/gallery_folder_screen.dart';
import 'package:surveycam/features/gallery/presentation/last_image_provider.dart';
import 'package:surveycam/features/location/presentation/location_viewmodel.dart';
import 'package:surveycam/features/overlay/domain/overlay_model.dart';
import 'package:surveycam/features/overlay/presentation/live_overlay_painter.dart';
import 'package:surveycam/features/overlay/presentation/overlay_preview_state.dart';
import 'package:surveycam/features/overlay/presentation/overlay_settings_provider.dart';
import 'package:surveycam/privacypolicy/privacyProvider.dart';
import '../domain/camera_lens_type.dart';


import 'package:surveycam/features/camera/data/CameraState.dart';
import 'camera_settings_provider.dart';
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
    final cameraVM = ref.read(cameraViewModelProvider.notifier);

    final lastImage = ref.watch(lastImageProvider);
    final focusPoint = ref.watch(focusPointProvider);

    final CameraController? controller = cameraState.controller;

    final isSelfieFlashActive = cameraState.currentLens == CameraLensType.front &&
        cameraState.flashMode == FlashMode.always;
    final uiColor = isSelfieFlashActive ? Colors.black87 : Colors.white;

    /// ===============================
    /// LISTENERS
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

          // Fetch Weather, Humidity, Air Quality
          final weatherData = await WeatherService.fetchWeather(
            position.latitude,
            position.longitude,
          );
          if (weatherData != null && mounted) {
            ref.read(overlayPreviewProvider.notifier).state =
                ref.read(overlayPreviewProvider.notifier).state.copyWith(
                  weather: weatherData.temp,
                  humidity: weatherData.humidity,
                  air: weatherData.airQuality,
                );
          }

          final settings = ref.read(cameraSettingsProvider);
          if (settings.autoFetchLocation) {
            final name = await LocationService.getLocationName(
              position.latitude,
              position.longitude,
            );
            if (name != null && mounted) {
              ref.read(overlayPreviewProvider.notifier).state =
                  ref.read(overlayPreviewProvider.notifier).state.copyWith(
                    note: name,
                  );
            }
          }
        });
      });
    }
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

    ref.listen<DeviceOrientation>(
      deviceOrientationProvider,
          (_, next) {
        cameraVM.updateOrientation(next);
      },
    );

    return SafeArea(
      child: Scaffold(
        backgroundColor: isSelfieFlashActive ? const Color(0xFFFDF0ED) : Colors.black,
        body: Stack(
          children: [
            Column(
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

                              final tapPosition = details.localPosition;
                              _focusTimer?.cancel();

                              ref.read(focusPointProvider.notifier).state = tapPosition;
                              cameraVM.setFocusPoint(tapPosition, previewSize);

                              setState(() => _showExposure = true);

                              _focusTimer = Timer(const Duration(seconds: 5), () {
                                if (!mounted) return;
                                if (ref.read(focusPointProvider) == tapPosition) {
                                  cameraVM.resetFocus();
                                  ref.read(focusPointProvider.notifier).state = null;
                                  setState(() => _showExposure = false);
                                }
                              });
                            },
                            onScaleUpdate: (details) {
                              if (controller == null || !controller.value.isInitialized) return;
                              if (details.scale != 1.0) {
                                cameraVM.setZoom(cameraState.zoom * details.scale);
                              } else {
                                final delta = -details.focalPointDelta.dy * 0.02;
                                if (delta != 0) {
                                  cameraVM.changeExposure(delta);
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
                                  Center(
                                    child: Padding(
                                      padding: isSelfieFlashActive
                                          ? const EdgeInsets.symmetric(horizontal: 16.0, vertical: 48.0)
                                          : EdgeInsets.zero,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(isSelfieFlashActive ? 1000 : 0),
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
                                    ),
                                  )
                                else
                                  const SizedBox.expand(
                                    child: ColoredBox(color: Colors.black),
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
                                          const Icon(Icons.camera_alt, color: Colors.white24, size: 50),
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

                          /// OVERLAY
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Consumer(
                                builder: (context, ref, child) {
                                  final overlayData = ref.watch(overlayPreviewProvider);
                                  final orientation = ref.watch(deviceOrientationProvider);
                                  final settings = ref.watch(overlaySettingsProvider);
                                  return CustomPaint(
                                    painter: LiveOverlayPainter(
                                      overlayData as OverlayData,
                                      orientation,
                                      settings: settings,
                                    ),
                                  );
                                },
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

                          /// TOP CONTROLS
                          Positioned(
                            top: 16,
                            left: 16,
                            child: IconButton(
                              icon: Icon(
                                Icons.info_outline,
                                color: isSelfieFlashActive ? Colors.black54 : Colors.amberAccent,
                              ),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (_) => const DeveloperInfoDialog(),
                                );
                              },
                            ),
                          ),
                          Positioned(
                            top: 16,
                            right: 0,
                            left: 0,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    cameraState.aspectRatio == CameraAspectRatio.ratio4_3
                                        ? Icons.crop_3_2
                                        : Icons.crop_16_9,
                                    color: uiColor,
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
                                  style: TextStyle(
                                    color: uiColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          Positioned(
                            top: 16,
                            right: 16,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.flip_camera_ios_outlined,
                                    color: uiColor,
                                  ),
                                  onPressed: cameraVM.switchCamera,
                                ),
                                const SizedBox(height: 16),
                                IconButton(
                                  icon: Icon(
                                    Icons.edit,
                                    color: uiColor,
                                  ),
                                  onPressed: () {
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => const NoteInputSheet(),
                                    );
                                  },
                                ),
                              ],
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
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  color: isSelfieFlashActive ? const Color(0xFFFDF0ED) : Colors.black,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                  ? uiColor.withOpacity(0.5)
                                  : uiColor,
                            ),
                            onPressed: cameraVM.cycleFlashMode,
                          ),
                          Text(
                            cameraState.flashMode == FlashMode.always ? "ON" : "OFF",
                            style: TextStyle(
                              color: uiColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      CaptureButton(
                        onCapture: () async {
                          if (!cameraState.isReady || _isCapturing) return;
                          setState(() => _isCapturing = true);
                          SystemSound.play(SystemSoundType.click);
                          HapticFeedback.mediumImpact();
                          try {
                            await cameraVM.capture(context);
                          } catch (e) {
                            debugPrint("Capture error: $e");
                          }
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
                              builder: (_) => const GalleryFolderScreen(),
                            ),
                          );
                        },
                        child: CircleAvatar(
                          radius: 22,
                          backgroundColor: isSelfieFlashActive ? Colors.black12 : Colors.grey.shade800,
                          backgroundImage: lastImage != null ? FileImage(lastImage) : null,
                          child: lastImage == null ? Icon(Icons.image, color: uiColor) : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isCapturing)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: (cameraState.currentLens == CameraLensType.front &&
                            cameraState.flashMode == FlashMode.always)
                        ? Colors.white
                        : Colors.black.withOpacity(0.3),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
