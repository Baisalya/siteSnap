import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:surveycam/core/services/location_service.dart';
import 'package:surveycam/core/services/rate_us_service.dart';
import 'package:surveycam/core/services/weather_service.dart';
import 'package:surveycam/core/utils/overlay_utils.dart';
import 'package:surveycam/core/utils/developer_info_dialog.dart';
import 'package:surveycam/core/utils/device_orientation_provider.dart';
import 'package:surveycam/core/utils/direction_utils.dart';
import 'package:surveycam/core/utils/focus_point_provider.dart';
import 'package:surveycam/features/compass/presentation/compass_provider.dart';
import 'package:surveycam/features/gallery/data/gallery_folder_screen.dart';
import 'package:surveycam/features/gallery/presentation/last_image_provider.dart';
import 'package:surveycam/features/location/presentation/location_viewmodel.dart';
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
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  bool _showExposure = false;
  Timer? _dateTimer;
  Timer? _focusTimer;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    /// INITIALIZE CAMERA FIRST, THEN NON-CRITICAL PROMPTS
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      unawaited(ref.read(cameraViewModelProvider.notifier).initialize());

      await RateUsService.init();
      if (mounted) {
        await RateUsService.showRateDialogIfMeetsCriteria(context);
      }
    });

    /// DATE TIME UPDATE TIMER
    _dateTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        final current = ref.read(overlayPreviewProvider);
        final settings = ref.read(overlaySettingsProvider);

        ref.read(overlayPreviewProvider.notifier).state = current.copyWith(
          dateTime: OverlayUtils.formatDateTime(
            DateTime.now(),
            settings.language,
            settings.use24HourTime,
          ),
        );
      },
    );
  }

  void _startRecordingTimer() {
    _recordingSeconds = 0;
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _recordingSeconds++;
        });
      }
    });
  }

  void _stopRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    setState(() {
      _recordingSeconds = 0;
    });
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Redundant refresh removed as ViewModel handles it efficiently
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dateTimer?.cancel();
    _focusTimer?.cancel();
    _recordingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final privacyAccepted = ref.watch(privacyProvider);
    final cameraState = ref.watch(cameraViewModelProvider);
    final cameraVM = ref.read(cameraViewModelProvider.notifier);
    final cameraSettings = ref.watch(cameraSettingsProvider);

    final lastImage = ref.watch(lastImageProvider);
    final focusPoint = ref.watch(focusPointProvider);

    final CameraController? controller = cameraState.controller;
    final isSelfieFlashActive =
        cameraState.currentLens == CameraLensType.front &&
            cameraState.flashMode == FlashMode.always;
    final uiColor = isSelfieFlashActive ? Colors.black87 : Colors.white;
    final backgroundColor =
        isSelfieFlashActive ? const Color(0xFFFEF7FF) : Colors.black;

    /// ===============================
    /// LISTENERS
    /// ===============================

    if (privacyAccepted == true) {
      ref.listen(locationStreamProvider, (_, next) async {
        next.whenData((position) async {
          final current = ref.read(overlayPreviewProvider);

          final serviceEnabled = await Geolocator.isLocationServiceEnabled();

          final permission = await Geolocator.checkPermission();

          if (!serviceEnabled) {
            ref.read(overlayPreviewProvider.notifier).state = current.copyWith(
              latitude: 0,
              longitude: 0,
              altitude: 0,
              locationWarning: "GPS turned off",
            );
            return;
          }

          if (permission == LocationPermission.denied ||
              permission == LocationPermission.deniedForever) {
            ref.read(overlayPreviewProvider.notifier).state = current.copyWith(
              latitude: 0,
              longitude: 0,
              altitude: 0,
              locationWarning: "Give location permission",
            );
            return;
          }

          if (position == null) {
            ref.read(overlayPreviewProvider.notifier).state = current.copyWith(
              latitude: 0,
              longitude: 0,
              altitude: 0,
              locationWarning: "Fetching location...",
            );
            return;
          }

          ref.read(overlayPreviewProvider.notifier).state = current.copyWith(
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
                      pressure: weatherData.pressure,
                    );
          }

          final settings = ref.read(cameraSettingsProvider);
          if (settings.autoFetchLocation) {
            final overlaySettings = ref.read(overlaySettingsProvider);
            final name = await LocationService.getLocationName(
              position.latitude,
              position.longitude,
              language: overlaySettings.language,
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
        ref.read(overlayPreviewProvider.notifier).state = current.copyWith(
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
        backgroundColor: backgroundColor,
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

                      final double targetAspectRatio =
                          cameraState.aspectRatio.portraitValue;

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

                              ref.read(focusPointProvider.notifier).state =
                                  tapPosition;
                              cameraVM.setFocusPoint(tapPosition, previewSize);

                              setState(() => _showExposure = true);

                              _focusTimer =
                                  Timer(const Duration(seconds: 5), () {
                                if (!mounted) return;
                                if (ref.read(focusPointProvider) ==
                                    tapPosition) {
                                  cameraVM.resetFocus();
                                  ref.read(focusPointProvider.notifier).state =
                                      null;
                                  setState(() => _showExposure = false);
                                }
                              });
                            },
                            onScaleUpdate: (details) {
                              if (controller == null ||
                                  !controller.value.isInitialized) {
                                return;
                              }
                              if (details.scale != 1.0) {
                                cameraVM
                                    .setZoom(cameraState.zoom * details.scale);
                              } else {
                                final delta =
                                    -details.focalPointDelta.dy * 0.02;
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
                                  SizedBox.expand(
                                      child: Center(
                                    child: AnimatedPadding(
                                      duration:
                                          const Duration(milliseconds: 300),
                                      curve: Curves.easeInOut,
                                      padding: isSelfieFlashActive
                                          ? const EdgeInsets.all(24.0)
                                          : EdgeInsets.zero,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                            isSelfieFlashActive ? 24 : 0),
                                        child: AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 300),
                                          curve: Curves.easeInOut,
                                          width: double.infinity,
                                          child: AspectRatio(
                                            aspectRatio: targetAspectRatio,
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                FittedBox(
                                                  fit: BoxFit.cover,
                                                  child: SizedBox(
                                                    width: controller.value
                                                        .previewSize!.height,
                                                    height: controller.value
                                                        .previewSize!.width,
                                                    child: CameraPreview(
                                                      controller,
                                                      key: ValueKey(controller
                                                          .description.name),
                                                    ),
                                                  ),
                                                ),

                                                /// OVERLAY (CONSTRAINED TO PREVIEW)
                                                IgnorePointer(
                                                  child: Consumer(
                                                    builder:
                                                        (context, ref, child) {
                                                      final overlayData = ref.watch(
                                                          overlayPreviewProvider);
                                                      final orientation = ref.watch(
                                                          deviceOrientationProvider);
                                                      final settings = ref.watch(
                                                          overlaySettingsProvider);
                                                      return CustomPaint(
                                                        painter:
                                                            LiveOverlayPainter(
                                                          overlayData,
                                                          orientation,
                                                          settings: settings,
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ))
                                else
                                  const SizedBox.expand(
                                    child: ColoredBox(color: Colors.black),
                                  ),
                                AnimatedOpacity(
                                  opacity: (cameraState.isReady &&
                                          controller != null &&
                                          cameraState.error == null)
                                      ? 0
                                      : 1,
                                  duration: const Duration(milliseconds: 250),
                                  child: Container(
                                    color: Colors.black,
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.camera_alt,
                                              color: Colors.white24, size: 50),
                                          if (cameraState.error != null) ...[
                                            const SizedBox(height: 16),
                                            Text(
                                              "Camera Error: ${cameraState.error}",
                                              style: const TextStyle(
                                                  color: Colors.white70),
                                              textAlign: TextAlign.center,
                                            ),
                                            TextButton(
                                              onPressed: () => ref
                                                  .read(cameraViewModelProvider
                                                      .notifier)
                                                  .initialize(),
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

                          /// REMOVED OLD OVERLAY POSITIONED.FILL

                          /// FOCUS + EXPOSURE UI
                          if (focusPoint != null)
                            Positioned.fill(
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: (focusPoint.dx - 35)
                                        .clamp(8.0, constraints.maxWidth - 120),
                                    top: (focusPoint.dy - 35).clamp(
                                        8.0, constraints.maxHeight - 200),
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 0.0, end: 1.0),
                                      duration:
                                          const Duration(milliseconds: 200),
                                      builder: (context, value, child) {
                                        return Transform.scale(
                                          scale: 0.8 + (0.2 * value),
                                          child: Opacity(
                                            opacity: value,
                                            child: child,
                                          ),
                                        );
                                      },
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 70,
                                                height: 70,
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                    color: Colors.yellow
                                                        .withValues(alpha: 0.8),
                                                    width: 1.0,
                                                  ),
                                                ),
                                                child: Center(
                                                  child: Container(
                                                    width: 4,
                                                    height: 4,
                                                    decoration:
                                                        const BoxDecoration(
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
                                                    const Icon(Icons.wb_sunny,
                                                        color: Colors.yellow,
                                                        size: 18),
                                                    const SizedBox(height: 8),
                                                    Container(
                                                      width: 2,
                                                      height: 100,
                                                      decoration: BoxDecoration(
                                                        color: Colors.white24,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(1),
                                                      ),
                                                      child:
                                                          FractionallySizedBox(
                                                        alignment: Alignment
                                                            .bottomCenter,
                                                        heightFactor: ((cameraState
                                                                        .exposure -
                                                                    cameraState
                                                                        .minExposure) /
                                                                (cameraState
                                                                        .maxExposure -
                                                                    cameraState
                                                                        .minExposure))
                                                            .clamp(0.0, 1.0),
                                                        child: Container(
                                                          decoration:
                                                              BoxDecoration(
                                                            color:
                                                                Colors.yellow,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        1),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          GestureDetector(
                                            onTap: () {
                                              _focusTimer?.cancel();
                                              cameraVM.resetFocus();
                                              ref
                                                  .read(focusPointProvider
                                                      .notifier)
                                                  .state = null;
                                              setState(
                                                  () => _showExposure = false);
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.black54,
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                    color: Colors.yellow
                                                        .withValues(alpha: 0.5),
                                                    width: 0.5),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                      Icons.filter_center_focus,
                                                      color: Colors.yellow,
                                                      size: 12),
                                                  SizedBox(width: 4),
                                                  Text("AUTO",
                                                      style: TextStyle(
                                                          color: Colors.yellow,
                                                          fontSize: 9,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          letterSpacing: 0.5)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
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
                                color: isSelfieFlashActive
                                    ? Colors.black54
                                    : Colors.amberAccent,
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
                                if (cameraState.isRecording)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _formatDuration(_recordingSeconds),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else ...[
                                  IconButton(
                                    icon: Icon(
                                      cameraState.aspectRatio ==
                                              CameraAspectRatio.ratio4_3
                                          ? Icons.crop_3_2
                                          : Icons.crop_16_9,
                                      color: uiColor,
                                    ),
                                    onPressed: () {
                                      final nextRatio =
                                          cameraState.aspectRatio ==
                                                  CameraAspectRatio.ratio4_3
                                              ? CameraAspectRatio.ratio16_9
                                              : CameraAspectRatio.ratio4_3;
                                      cameraVM.setAspectRatio(nextRatio);
                                    },
                                  ),
                                  Text(
                                    cameraState.aspectRatio.label,
                                    style: TextStyle(
                                      color: uiColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          Positioned(
                            top: 16,
                            right: 16,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.flip_camera_ios_outlined,
                                    color: uiColor,
                                  ),
                                  onPressed: cameraVM.switchCamera,
                                ),
                                if (!cameraState.isRecording) ...[
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
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  color: backgroundColor,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Mode Selector
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelfieFlashActive
                              ? Colors.black.withValues(alpha: 0.05)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildModeButton(
                              label: "PHOTO",
                              active:
                                  cameraState.cameraMode == CameraMode.photo,
                              onTap: () =>
                                  cameraVM.setCameraMode(CameraMode.photo),
                              uiColor: uiColor,
                            ),
                            const SizedBox(width: 32),
                            _buildModeButton(
                              label: "VIDEO",
                              active:
                                  cameraState.cameraMode == CameraMode.video,
                              onTap: () =>
                                  cameraVM.setCameraMode(CameraMode.video),
                              uiColor: uiColor,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 100,
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            SizedBox(
                              width: 60,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      child: Icon(
                                        cameraState.flashMode ==
                                                FlashMode.always
                                            ? Icons.flash_on
                                            : Icons.flash_off,
                                        key: ValueKey(cameraState.flashMode),
                                        color: cameraState.flashMode ==
                                                FlashMode.off
                                            ? uiColor.withValues(alpha: 0.4)
                                            : Colors.amberAccent,
                                      ),
                                    ),
                                    onPressed: cameraVM.cycleFlashMode,
                                  ),
                                  Text(
                                    cameraState.flashMode == FlashMode.always
                                        ? "FLASH ON"
                                        : "FLASH OFF",
                                    style: TextStyle(
                                      color: uiColor.withValues(alpha: 0.6),
                                      fontSize: 8,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CaptureButton(
                                  isRecording: cameraState.isRecording,
                                  mode: cameraState.cameraMode,
                                  onCapture: () async {
                                    if (!cameraState.isReady || _isCapturing) {
                                      return;
                                    }

                                    if (cameraState.cameraMode ==
                                        CameraMode.video) {
                                      if (cameraState.isRecording) {
                                        _stopRecordingTimer();
                                        await cameraVM
                                            .stopVideoRecording(context);
                                      } else {
                                        final started = await cameraVM
                                            .startVideoRecording();
                                        if (started && mounted) {
                                          _startRecordingTimer();
                                        }
                                      }
                                      return;
                                    }

                                    setState(() => _isCapturing = true);
                                    SystemSound.play(SystemSoundType.click);
                                    HapticFeedback.mediumImpact();

                                    try {
                                      final path = await cameraVM.capture();

                                      // Instant shutter feedback removal
                                      if (mounted) {
                                        setState(() => _isCapturing = false);
                                      }

                                      if (path != null && context.mounted) {
                                        // Fire-and-forget navigation for zero-lag feeling
                                        unawaited(cameraVM.handlePostCapture(
                                            path, context));
                                      }
                                    } catch (e) {
                                      debugPrint("Capture error: $e");
                                      if (mounted) {
                                        setState(() => _isCapturing = false);
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                            SizedBox(
                              width: 60,
                              child: Center(
                                child: GestureDetector(
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const GalleryFolderScreen(),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: uiColor.withValues(alpha: 0.2),
                                          width: 1),
                                    ),
                                    child: CircleAvatar(
                                      radius: 20,
                                      backgroundColor: isSelfieFlashActive
                                          ? Colors.black12
                                          : Colors.grey.shade900,
                                      backgroundImage: lastImage != null
                                          ? FileImage(lastImage)
                                          : null,
                                      child: lastImage == null
                                          ? Icon(Icons.image,
                                              color: uiColor.withValues(
                                                  alpha: 0.5),
                                              size: 20)
                                          : null,
                                    ),
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
              ],
            ),
            if (_isCapturing)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: (cameraState.currentLens == CameraLensType.front &&
                            cameraState.flashMode == FlashMode.always)
                        ? Colors.white
                        : Colors.black.withValues(alpha: 0.3),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton({
    required String label,
    required bool active,
    required VoidCallback onTap,
    required Color uiColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color:
                  active ? Colors.amberAccent : uiColor.withValues(alpha: 0.5),
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          if (active)
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: Colors.amberAccent,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}
