import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart' hide CameraLensType;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:surveycam/core/di/providers.dart';
import 'package:surveycam/core/permissions/permission_service.dart';
import 'package:surveycam/core/utils/device_orientation_provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:surveycam/core/services/background_video_task.dart';
import 'package:surveycam/core/services/video_processing_job.dart';
import 'package:surveycam/core/utils/gallery_saver.dart';
import 'package:surveycam/features/camera/data/CameraState.dart';
import 'package:surveycam/features/camera/domain/camera_lens_type.dart';
import 'package:surveycam/features/camera/presentation/camera_settings_provider.dart';
import 'package:surveycam/features/overlay/presentation/overlay_settings_provider.dart';
import 'package:surveycam/features/gallery/presentation/image_preview_screen.dart';
import 'package:surveycam/features/gallery/presentation/last_image_provider.dart';
import 'package:surveycam/features/location/presentation/location_viewmodel.dart';
import 'package:surveycam/features/overlay/domain/overlay_model.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';
import 'package:surveycam/features/overlay/presentation/captured_overlay_provider.dart';
import 'package:surveycam/features/overlay/presentation/overlay_preview_state.dart';
import 'package:surveycam/features/gallery/data/sitesnap_gallery_repository.dart';
import 'package:surveycam/features/overlay/domain/video_overlay_sample.dart';
import 'package:surveycam/features/projects/presentation/project_provider.dart';

final cameraViewModelProvider =
    StateNotifierProvider<CameraViewModel, CameraState>((ref) {
  return CameraViewModel(ref);
});

const Duration _photoCaptureTimeout = Duration(seconds: 12);
const Duration _flashExposureSettleDelay = Duration(milliseconds: 60);

class CameraViewModel extends StateNotifier<CameraState>
    with WidgetsBindingObserver {
  final Ref ref;

  double _currentExposure = 0.0;
  double _minExposure = 0.0;
  double _maxExposure = 0.0;

  bool _isCameraStable = false;
  bool _isInitializing = false;
  bool _isDisposing = false;
  final bool _isRestarting = false;
  bool _captureInFlight = false;
  bool _startRecordingInFlight = false;
  bool _stopRecordingInFlight = false;
  Timer? _videoHistoryTimer;

  // Optimized overlay history storage
  final List<VideoOverlaySample> _videoDataHistory = [];
  DateTime? _recordingStartTime;

  bool get isCameraStable => _isCameraStable;
  double get exposureValue => _currentExposure;

  CameraViewModel(this.ref) : super(const CameraState(isReady: false)) {
    WidgetsBinding.instance.addObserver(this);
    ref.listen<OverlayData>(
      overlayPreviewProvider,
      (_, __) => _recordCurrentVideoOverlaySample(),
    );
    ref.listen<OverlaySettings>(
      overlaySettingsProvider,
      (_, __) => _recordCurrentVideoOverlaySample(),
    );
    
    // Defer initialization work to avoid blocking the main thread during constructor execution (ANR prevention)
    Future.microtask(() {
      if (mounted) {
        _initBackgroundService();
        unawaited(_resumePendingVideoProcessing());
      }
    });
    // Removed automatic initialize() to allow manual/early trigger
  }

  void _initBackgroundService() {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
  }

  void _onReceiveTaskData(dynamic message) {
    if (message is Map<String, dynamic>) {
      if (message['type'] == 'progress') {
        state = state.copyWith(
          processingProgress: message['value'],
          processingMessage:
              message['message'] as String? ?? 'Processing video...',
          videoProcessingError: null,
        );
      } else if (message['type'] == 'complete') {
        final warning = message['warning'] as String?;
        state = state.copyWith(
          clearProcessingProgress: true,
          processingMessage: warning ?? 'Video saved successfully.',
          videoProcessingError: null,
        );
        unawaited(ref.read(galleryFilesProvider.notifier).refresh());
      } else if (message['type'] == 'image_complete') {
        final originalPath = message['originalPath'] as String?;
        final savedPath = message['path'] as String?;
        if (savedPath != null && savedPath.isNotEmpty) {
          final savedFile = File(savedPath);
          ref.read(lastImageProvider.notifier).state = savedFile;
          if (originalPath != null && originalPath.isNotEmpty) {
            ref
                .read(galleryProcessingProvider.notifier)
                .complete(File(originalPath), savedFile);
            ref
                .read(galleryFilesProvider.notifier)
                .showFileImmediately(savedFile, replace: File(originalPath));
          } else {
            ref.read(galleryFilesProvider.notifier).showFileImmediately(
                  savedFile,
                );
          }
        } else {
          unawaited(ref.read(galleryFilesProvider.notifier).refresh());
        }
      } else if (message['type'] == 'image_error') {
        final originalPath = message['originalPath'] as String?;
        if (originalPath != null && originalPath.isNotEmpty) {
          ref.read(galleryProcessingProvider.notifier).fail(File(originalPath));
        }
      } else if (message['type'] == 'error') {
        state = state.copyWith(
          clearProcessingProgress: true,
          processingMessage: 'Video processing failed.',
          videoProcessingError: _friendlyVideoError(message['error']),
        );
      } else if (message['type'] == 'cancelled') {
        state = state.copyWith(
          clearProcessingProgress: true,
          processingMessage:
              message['message'] as String? ?? 'Processing cancelled.',
          videoProcessingError: null,
        );
      }
    }
  }

  String _friendlyVideoError(Object? error) {
    final text = error?.toString().trim();
    if (text == null || text.isEmpty) {
      return 'Video processing failed. Please try recording again.';
    }
    return text.replaceFirst('Exception: ', '');
  }

  bool _isNativeCameraNullPointer(Object error) {
    final text = error.toString();
    return text.contains('CameraException') &&
        text.contains('NullPointerException');
  }

  String _friendlyStopRecordingError(Object error) {
    if (_isNativeCameraNullPointer(error)) {
      return 'Camera lost the active recording session before it could finalize the video. Please try recording again.';
    }
    return _friendlyVideoError(error);
  }

  // ================= INIT =================

  Future<void> initialize() async {
    if (_isInitializing || _isDisposing) return;
    _isInitializing = true;

    state = state.copyWith(error: null);

    try {
      await PermissionService.requestCameraAndMicrophone();

      final repo = ref.read(cameraRepositoryProvider);

      try {
        await repo.initialize(state.currentLens);
      } catch (e) {
        debugPrint('Repo init error: $e');
        // Try one retry if it fails immediately with a smaller delay
        await Future.delayed(const Duration(milliseconds: 100));
        await repo.initialize(state.currentLens);
      }

      final controller = repo.controller;
      if (controller == null) {
        state = state.copyWith(
            isReady: false, error: "Camera controller failed to initialize");
        return;
      }

      // Ensure the controller is initialized before proceeding
      if (!controller.value.isInitialized) {
        await controller.initialize();
      }

      if (controller.value.isInitialized) {
        _isCameraStable = true;

        state = state.copyWith(
          isReady: true,
          controller: controller,
          exposure: _currentExposure,
          minExposure: _minExposure,
          maxExposure: _maxExposure,
          zoom: 1.0,
          minZoom: state.minZoom,
          maxZoom: state.maxZoom,
          error: null,
        );

        unawaited(_configureCameraAfterReady(controller));
        unawaited(_warmUpAfterCameraReady());
      } else {
        state = state.copyWith(
            isReady: false,
            error: "Camera controller not initialized after setup");
      }
    } catch (e) {
      debugPrint('Init error: $e');
      String errorMessage = e.toString();
      if (errorMessage.contains('CameraException')) {
        errorMessage =
            "Camera Error: Please ensure no other app is using the camera.";
      }
      state = state.copyWith(isReady: false, error: errorMessage);
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _configureCameraAfterReady(CameraController controller) async {
    try {
      if (!mounted || !controller.value.isInitialized) return;

      // 🔥 Optimization: Parallelize initial camera configuration to reduce startup delay
      await Future.wait([
        controller.setFlashMode(FlashMode.off),
        controller.setFocusMode(FocusMode.auto),
        controller.setExposureMode(ExposureMode.auto),
        controller.setFocusPoint(const Offset(0.5, 0.5)),
        controller.setExposurePoint(const Offset(0.5, 0.5)),
      ]).catchError((e) {
        debugPrint("Deferred camera configuration partial failure: $e");
        return [];
      });

      final caps = await Future.wait([
        controller.getMinExposureOffset(),
        controller.getMaxExposureOffset(),
        controller.getMinZoomLevel(),
        controller.getMaxZoomLevel(),
      ]);

      if (!mounted || state.controller != controller) return;

      _minExposure = caps[0];
      _maxExposure = caps[1];
      _currentExposure = 0.0.clamp(_minExposure, _maxExposure);

      try {
        await controller.setExposureOffset(_currentExposure);
      } catch (e) {
        debugPrint("Initial exposure offset error: $e");
      }

      if (!mounted || state.controller != controller) return;

      state = state.copyWith(
        exposure: _currentExposure,
        minExposure: _minExposure,
        maxExposure: _maxExposure,
        minZoom: caps[2],
        maxZoom: caps[3],
      );
    } catch (e) {
      debugPrint('Deferred camera setup skipped: $e');
    }
  }

  Future<void> _warmUpAfterCameraReady() async {
    try {
      final controller = state.controller;
      if (controller != null && controller.value.isInitialized) {
        unawaited(controller.prepareForVideoRecording().catchError((e) {
          debugPrint("Video pre-warm skipped: $e");
        }));
      }
      await GallerySaver.warmUp();
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      await PermissionService.requestLocationIfNeeded();
      if (mounted) {
        ref.invalidate(locationStreamProvider);
      }
    } catch (e) {
      debugPrint('Background warm-up skipped: $e');
    }
  }

  // ================= ORIENTATION =================

  void updateOrientation(DeviceOrientation orientation) {
    if (state.orientation != orientation) {
      state = state.copyWith(orientation: orientation);
      _recordCurrentVideoOverlaySample();
    }
  }

  void _recordCurrentVideoOverlaySample({bool force = false}) {
    final startedAt = _recordingStartTime;
    if (startedAt == null) return;
    if (!force && !state.isRecording) return;

    final timestamp = DateTime.now()
        .difference(startedAt)
        .inMilliseconds
        .clamp(0, 1 << 31)
        .toInt();
    final data = ref.read(overlayPreviewProvider);
    final settings = ref.read(overlaySettingsProvider);
    final orientation = state.orientation;

    if (!force && _videoDataHistory.isNotEmpty) {
      final previous = _videoDataHistory.last;
      final duplicateState = previous.data == data &&
          previous.settings == settings &&
          previous.orientation == orientation;
      if (duplicateState && timestamp - previous.timestampMs < 80) {
        return;
      }
    }

    _videoDataHistory.add(VideoOverlaySample(
      data: data,
      orientation: orientation,
      settings: settings,
      timestampMs: timestamp,
    ));
  }

  // ================= LIFECYCLE =================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final appState = state;
    debugPrint("AppLifecycleState: $appState");

    if (appState == AppLifecycleState.inactive ||
        appState == AppLifecycleState.paused ||
        appState == AppLifecycleState.hidden) {
      try {
        final controller = this.state.controller;
        if (controller != null) {
          if ((appState == AppLifecycleState.paused ||
                  appState == AppLifecycleState.hidden) &&
              this.state.isRecording) {
            await stopVideoRecordingInBackground();
            return;
          }

          // Soft quench flash immediately
          await _softFlashQuench(controller);

          if (appState == AppLifecycleState.paused ||
              appState == AppLifecycleState.hidden) {
            // 🔥 INSTAGRAM-STYLE OPTIMIZATION:
            // Instead of fully disposing, we only pause the preview.
            // This keeps the hardware "warmed up" and the OS session alive
            // so resuming is near-instant.
            try {
              await controller.pausePreview();
              debugPrint("Camera preview paused for backgrounding.");
            } catch (e) {
              debugPrint("Error pausing preview: $e. Falling back to dispose.");
              _isDisposing = true;
              await ref.read(cameraRepositoryProvider).dispose();
              this.state =
                  this.state.copyWith(clearController: true, isReady: false);
              _isDisposing = false;
            }
          }
        }
      } catch (e) {
        debugPrint("Error on backgrounding: $e");
      }
    }

    if (appState == AppLifecycleState.resumed) {
      final controller = this.state.controller;
      if (controller != null && controller.value.isInitialized) {
        try {
          await controller.resumePreview();
          // Health check: verify hardware session is still valid after resume
          await controller.getMinZoomLevel();
          debugPrint("Camera preview resumed and verified.");
          // 🔥 Nudge the UI to rebuild the texture surface
          this.state = this.state.copyWith();
        } catch (e) {
          debugPrint(
              "Instant resume or health check failed: $e. Re-initializing...");
          await initialize();
        }
      } else {
        await initialize();
      }
    }
  }

  // ================= REFRESH =================

  Future<void> refreshCamera() async {
    debugPrint("Refreshing camera manually...");
    await ref.read(cameraRepositoryProvider).dispose();
    state = state.copyWith(clearController: true, isReady: false, error: null);
    await initialize();
  }

  // ================= FOCUS =================

  Future<void> setFocusPoint(Offset position, Size previewSize) async {
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      final dx = (position.dx / previewSize.width).clamp(0.0, 1.0);
      final dy = (position.dy / previewSize.height).clamp(0.0, 1.0);

      state = state.copyWith(isManualFocus: true);

      // Wrap individual calls in try-catch as some devices might fail on one but not the other
      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (e) {
        debugPrint("Error setting focus mode: $e");
      }

      try {
        await controller.setExposureMode(ExposureMode.auto);
      } catch (e) {
        debugPrint("Error setting exposure mode: $e");
      }

      try {
        await controller.setFocusPoint(Offset(dx, dy));
      } catch (e) {
        debugPrint("Error setting focus point: $e");
      }

      try {
        await controller.setExposurePoint(Offset(dx, dy));
      } catch (e) {
        debugPrint("Error setting exposure point: $e");
      }
    } catch (e) {
      debugPrint("Overall focus point error: $e");
    }
  }

  Future<void> resetFocus() async {
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      state = state.copyWith(isManualFocus: false);

      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);

      // Reset points to center
      await controller.setFocusPoint(null);
      await controller.setExposurePoint(null);
    } catch (e) {
      debugPrint("Reset focus error: $e");
    }
  }

  // ================= EXPOSURE =================

  Future<void> changeExposure(double delta) async {
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      _currentExposure =
          (_currentExposure + delta).clamp(_minExposure, _maxExposure);

      await controller.setExposureOffset(_currentExposure);

      state = state.copyWith(exposure: _currentExposure);
    } catch (e) {
      debugPrint("Exposure error: $e");
    }
  }

  // ================= ZOOM =================

  Future<void> setZoom(double zoom) async {
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      final clampedZoom = zoom.clamp(state.minZoom, state.maxZoom);
      await controller.setZoomLevel(clampedZoom);
      state = state.copyWith(zoom: clampedZoom);
    } catch (e) {
      debugPrint("Zoom error: $e");
    }
  }

  /// 🔥 THE NUCLEAR FLASH KILL
  /// Specifically designed for Android devices where the LED driver "latches"
  /// on in dark environments when using Auto Flash.
  /// A softer quench that doesn't flicker
  Future<void> _softFlashQuench(CameraController controller) async {
    try {
      if (!controller.value.isInitialized) return;
      await controller.setFlashMode(FlashMode.off);
      await Future.delayed(const Duration(milliseconds: 40));
    } catch (_) {}
  }

  /// The heavy-duty reset for stuck drivers (causes a brief flicker)
  Future<void> _nuclearFlashKill(CameraController controller) async {
    try {
      if (!controller.value.isInitialized) return;

      await controller.setFlashMode(FlashMode.off);
      await Future.delayed(const Duration(milliseconds: 50));

      // Torch "kick" to reset the hardware driver
      await controller.setFlashMode(FlashMode.torch);
      await Future.delayed(const Duration(milliseconds: 80));
      await controller.setFlashMode(FlashMode.off);

      // Cooldown to let sensor recover from the burst
      await Future.delayed(const Duration(milliseconds: 80));
    } catch (e) {
      debugPrint("Nuclear flash kill error: $e");
    }
  }

  // ================= FLASH =================

  Future<void> setFlashMode(FlashMode mode) async {
    state = state.copyWith(flashMode: mode);

    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      if (mode == FlashMode.off) {
        await controller.setFlashMode(FlashMode.off);
      } else {
        // If recording video, enable torch immediately
        if (state.isRecording && state.currentLens != CameraLensType.front) {
          await controller.setFlashMode(FlashMode.torch);
        } else {
          // For photos, we keep it OFF and only enable it during capture to prevent "sticking"
          await controller.setFlashMode(FlashMode.off);
        }
      }
    } catch (e) {
      debugPrint("Error setting flash mode: $e");
    }
  }

  Future<void> cycleFlashMode() async {
    final nextMode =
        state.flashMode == FlashMode.off ? FlashMode.always : FlashMode.off;
    await setFlashMode(nextMode);
  }

  void setAspectRatio(CameraAspectRatio ratio) {
    state = state.copyWith(aspectRatio: ratio);
  }

  // ================= CAMERA SWITCH =================

  Future<void> switchCamera() async {
    if (_isInitializing || _isRestarting) return;

    final wasRecording = state.isRecording;
    if (wasRecording) {
      try {
        final repo = ref.read(cameraRepositoryProvider);
        final segmentFile = await repo.stopVideoRecording();
        final segment = VideoSegment(
          path: segmentFile.path,
          lens: state.currentLens,
          mirror: _shouldMirrorSegment(state.currentLens),
        );
        state = state.copyWith(
          videoSegments: [...state.videoSegments, segment],
        );
        // Note: We don't set isRecording to false here to avoid UI flicker
        // and we don't stop the _videoHistoryTimer yet
      } catch (e) {
        debugPrint("Error saving segment during switch: $e");
      }
    }

    final nextLens = state.currentLens == CameraLensType.front
        ? CameraLensType.normal
        : CameraLensType.front;

    state = state.copyWith(
        currentLens: nextLens, isReady: false, clearController: true);

    try {
      final repo = ref.read(cameraRepositoryProvider);
      await repo.initialize(nextLens);

      final controller = repo.controller;
      if (controller != null) {
        if (!controller.value.isInitialized) {
          await controller.initialize();
        }

        try {
          _minExposure = await controller.getMinExposureOffset();
          _maxExposure = await controller.getMaxExposureOffset();
          final minZoom = await controller.getMinZoomLevel();
          final maxZoom = await controller.getMaxZoomLevel();

          state = state.copyWith(
            isReady: true,
            controller: controller,
            exposure: 0.0,
            minExposure: _minExposure,
            maxExposure: _maxExposure,
            zoom: 1.0,
            minZoom: minZoom,
            maxZoom: maxZoom,
            error: null,
          );
        } catch (e) {
          debugPrint("Error getting camera capabilities during switch: $e");
          state = state.copyWith(
              isReady: true, controller: controller, error: null);
        }

        if (wasRecording) {
          // Restart recording segment without clearing history/sequence
          final repo = ref.read(cameraRepositoryProvider);
          if (state.flashMode == FlashMode.always &&
              state.currentLens != CameraLensType.front) {
            await controller.setFlashMode(FlashMode.torch);
          }
          await repo.startVideoRecording();
        }
      }
    } catch (e) {
      debugPrint("Switch camera error: $e");
      state = state.copyWith(
          isReady: false, error: e.toString(), isRecording: false);
      _videoHistoryTimer?.cancel();
    }
  }

  // ================= CAPTURE =================

  void setCameraMode(CameraMode mode) {
    state = state.copyWith(cameraMode: mode);
  }

  bool _shouldMirrorSegment(CameraLensType lens) {
    return lens == CameraLensType.front &&
        ref.read(cameraSettingsProvider).mirrorFrontVideo;
  }

  Future<void> setFrontVideoMirroring(bool mirror) async {
    if (state.currentLens != CameraLensType.front || !state.isRecording) {
      await ref
          .read(cameraSettingsProvider.notifier)
          .setMirrorFrontVideo(mirror);
      return;
    }

    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) {
      await ref
          .read(cameraSettingsProvider.notifier)
          .setMirrorFrontVideo(mirror);
      return;
    }

    var segmentClosed = false;

    try {
      final repo = ref.read(cameraRepositoryProvider);
      final segmentFile = await repo.stopVideoRecording();
      segmentClosed = true;
      final segment = VideoSegment(
        path: segmentFile.path,
        lens: state.currentLens,
        mirror: _shouldMirrorSegment(state.currentLens),
      );

      state = state.copyWith(
        videoSegments: [...state.videoSegments, segment],
      );

      await ref
          .read(cameraSettingsProvider.notifier)
          .setMirrorFrontVideo(mirror);

      await repo.startVideoRecording();
      state = state.copyWith(isRecording: true);
    } catch (e) {
      debugPrint("Mirror toggle while recording failed: $e");
      await ref
          .read(cameraSettingsProvider.notifier)
          .setMirrorFrontVideo(mirror);
      if (segmentClosed) {
        _videoHistoryTimer?.cancel();
        state = state.copyWith(isRecording: false);
      }
    }
  }

  Future<String?> capture() async {
    final controller = state.controller;

    if (!state.isReady ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        state.isCapturing ||
        _captureInFlight ||
        state.isRecording) {
      // HEALTH CHECK: If we think we are ready but controller is null or not init, trigger recovery
      if (state.isReady &&
          (controller == null || !controller.value.isInitialized)) {
        debugPrint(
            "Camera state desync detected during capture. Triggering recovery...");
        await refreshCamera();
      }

      return null;
    }

    _captureInFlight = true;
    unawaited(HapticFeedback.mediumImpact());

    final overlayData = ref.read(overlayPreviewProvider);
    ref.read(capturedOverlayProvider.notifier).state = overlayData;
    final deviceOrientation = ref.read(deviceOrientationProvider);

    state = state.copyWith(
      isCapturing: true,
      captureOrientation: deviceOrientation,
      captureLens: state.currentLens,
    );

    try {
      final repo = ref.read(cameraRepositoryProvider);

      // 🔥 SPEED OPTIMIZATION: Skip redundant exposure preparation if we are already in
      // a standard auto state with Flash OFF. This avoids re-triggering AE/AF scans.
      if (state.isManualFocus ||
          state.flashMode != FlashMode.off ||
          _currentExposure != 0.0) {
        await _prepareSmartPhotoExposure(controller);
      }

      if (state.flashMode == FlashMode.always) {
        if (state.currentLens == CameraLensType.front) {
          await Future.delayed(const Duration(milliseconds: 20));
        } else {
          await controller.setFlashMode(FlashMode.torch);
          await Future.delayed(_flashExposureSettleDelay);
        }
      }

      // Actual capture - native speed is controlled by the camera plugin/driver
      final path = await repo.takePicture().timeout(_photoCaptureTimeout);

      if (state.flashMode == FlashMode.always) {
        unawaited(_nuclearFlashKill(controller));
      } else if (state.flashMode != FlashMode.off) {
        unawaited(_softFlashQuench(controller));
      }

      unawaited(HapticFeedback.lightImpact());
      return path;
    } on TimeoutException catch (e) {
      debugPrint('Capture timeout: $e');
      await refreshCamera();
      return null;
    } catch (e) {
      debugPrint('Capture error: $e');
      if (e.toString().contains('CameraException')) {
        debugPrint(
            "Critical camera exception during capture. Attempting automatic recovery...");
        await refreshCamera();
      }
      return null;
    } finally {
      // 🔓 RESTORATION (Non-blocking cleanup)
      _captureInFlight = false;
      unawaited(_restoreCameraState(controller));
      state = state.copyWith(isCapturing: false);
    }
  }

  Future<void> _prepareSmartPhotoExposure(CameraController controller) async {
    try {
      if (!controller.value.isInitialized) return;

      final List<Future> tasks = [];

      // Only re-apply auto mode if we are doing a manual reset
      if (!state.isManualFocus) {
        tasks.add(
            controller.setExposureMode(ExposureMode.auto).catchError((_) {}));
        tasks.add(controller.setFocusMode(FocusMode.auto).catchError((_) {}));
        tasks.add(controller
            .setExposurePoint(const Offset(0.5, 0.5))
            .catchError((_) {}));
        tasks.add(controller
            .setFocusPoint(const Offset(0.5, 0.5))
            .catchError((_) {}));
      }

      // Re-apply current exposure offset if it's set
      if (_currentExposure != 0.0) {
        tasks.add(controller
            .setExposureOffset(
                _currentExposure.clamp(_minExposure, _maxExposure))
            .catchError((_) => 0.0));
      }

      if (tasks.isNotEmpty) {
        await Future.wait(tasks);
      }
    } catch (e) {
      debugPrint("Smart exposure preparation skipped: $e");
    }
  }

  Future<void> _restoreCameraState(CameraController? controller) async {
    try {
      if (controller == null || !controller.value.isInitialized) return;

      final List<Future> cleanupTasks = [
        controller.setFlashMode(FlashMode.off),
      ];

      // Only reset focus/exposure if they were altered by manual interaction
      if (state.isManualFocus) {
        cleanupTasks.add(controller.setFocusMode(FocusMode.auto));
        cleanupTasks.add(controller.setExposureMode(ExposureMode.auto));
        cleanupTasks.add(controller.setFocusPoint(null));
        cleanupTasks.add(controller.setExposurePoint(null));
      }

      // Also ensure exposure offset is restored if it was non-zero
      if (_currentExposure != 0.0) {
        cleanupTasks.add(controller.setExposureOffset(_currentExposure));
      }

      await Future.wait(cleanupTasks.map((t) => t.catchError((e) => null)));

      // Resume preview if needed by the specific device/plugin state
      await controller.resumePreview().catchError((e) => null);
    } catch (e) {
      debugPrint("Restoration error: $e");
    }
  }

  Future<void> handlePostCapture(
    String path,
    BuildContext context,
  ) async {
    try {
      final originalFile = File(path);
      if (!context.mounted) return;

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImagePreviewScreen(
            originalFile: originalFile,
            processedFile: originalFile,
          ),
        ),
      );

      if (result is Future<File?>) {
        ref.read(lastImageProvider.notifier).state = originalFile;
        ref
            .read(galleryFilesProvider.notifier)
            .showFileImmediately(originalFile);
        unawaited(result.then((savedFile) {
          if (savedFile != null) {
            ref.read(lastImageProvider.notifier).state = savedFile;
            ref
                .read(galleryFilesProvider.notifier)
                .showFileImmediately(savedFile, replace: originalFile);
          }
        }));
      } else if (result is File) {
        ref.read(lastImageProvider.notifier).state = result;
        ref.read(galleryFilesProvider.notifier).showFileImmediately(result);
      } else if (result != null) {
        ref.read(lastImageProvider.notifier).state = originalFile;
        ref
            .read(galleryFilesProvider.notifier)
            .showFileImmediately(originalFile);
      }
    } catch (e) {
      debugPrint("Post capture error: $e");
    }
  }

  Future<bool> startVideoRecording({bool clearSegments = true}) async {
    final controller = state.controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        state.isRecording ||
        _startRecordingInFlight ||
        _stopRecordingInFlight ||
        (state.processingProgress != null)) {
      return false;
    }

    _startRecordingInFlight = true;
    try {
      state = state.copyWith(
        processingMessage: null,
        videoProcessingError: null,
      );
      final repo = ref.read(cameraRepositoryProvider);

      if (state.flashMode == FlashMode.always &&
          state.currentLens != CameraLensType.front) {
        await controller.setFlashMode(FlashMode.torch);
      }

      await repo.startVideoRecording();

      // Start history tracking
      _videoHistoryTimer?.cancel();
      if (clearSegments || state.videoSegments.isEmpty) {
        _videoDataHistory.clear();
      }
      _recordingStartTime = DateTime.now();

      // Sample overlay at 2 FPS
      _videoHistoryTimer =
          Timer.periodic(const Duration(milliseconds: 500), (timer) {
        if (!state.isRecording) {
          timer.cancel();
          return;
        }

        // 🔥 FRESH DATA CAPTURE
        _recordCurrentVideoOverlaySample(force: true);
      });

      // Initial sample
      _recordCurrentVideoOverlaySample(force: true);

      state = state.copyWith(
        isRecording: true,
        videoSegments: clearSegments ? <VideoSegment>[] : state.videoSegments,
        processingMessage: null,
        videoProcessingError: null,
      );
      unawaited(HapticFeedback.heavyImpact());
      return true;
    } catch (e) {
      debugPrint("Start recording error: $e");
      return false;
    } finally {
      _startRecordingInFlight = false;
    }
  }

  Future<void> stopVideoRecording(BuildContext context) async {
    await _stopVideoRecording(context: context);
  }

  Future<void> stopVideoRecordingInBackground() async {
    await _stopVideoRecording();
  }

  Future<void> cancelVideoProcessing() async {
    if (state.processingProgress == null) return;

    state = state.copyWith(
      clearProcessingProgress: true,
      processingMessage: 'Processing cancelled.',
      videoProcessingError: null,
    );

    await VideoProcessingTaskHandler.cancelProcessing();
  }

  void clearVideoProcessingStatus() {
    state = state.copyWith(
      processingMessage: null,
      videoProcessingError: null,
    );
  }

  Future<void> _stopVideoRecording({BuildContext? context}) async {
    final controller = state.controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        !state.isRecording ||
        _stopRecordingInFlight) {
      return;
    }

    _stopRecordingInFlight = true;
    try {
      final repo = ref.read(cameraRepositoryProvider);
      _videoHistoryTimer?.cancel();
      _videoHistoryTimer = null;

      final lastSegmentFile = await repo.stopVideoRecording();
      final lastSegment = VideoSegment(
        path: lastSegmentFile.path,
        lens: state.currentLens,
        mirror: _shouldMirrorSegment(state.currentLens),
      );
      final allSegments = [...state.videoSegments, lastSegment];
      final totalDurationMs = _recordingStartTime == null
          ? 0
          : DateTime.now().difference(_recordingStartTime!).inMilliseconds;

      // Capture data needed for processing before clearing local state
      _recordCurrentVideoOverlaySample(force: true);
      final history = List<VideoOverlaySample>.from(_videoDataHistory);
      if (history.isEmpty) {
        history.add(VideoOverlaySample(
          data: ref.read(overlayPreviewProvider),
          orientation: state.orientation,
          settings: ref.read(overlaySettingsProvider),
          timestampMs: 0,
        ));
      }

      // Update state: stop recording and start processing overlay
      state = state.copyWith(
        isRecording: false,
        processingProgress: 0.05,
        processingMessage: 'Processing video in background...',
        videoProcessingError: null,
      );
      unawaited(HapticFeedback.mediumImpact());

      if (state.flashMode == FlashMode.always) {
        await _softFlashQuench(controller);
      }

      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text("Processing video in background. Recording is paused."),
            duration: Duration(milliseconds: 2200),
          ),
        );
      }

      final now = DateTime.now();
      final job = VideoProcessingJob(
        id: 'video_${now.microsecondsSinceEpoch}',
        segments: allSegments
            .map((segment) => VideoProcessingSegment(
                  path: segment.path,
                  lens: segment.lens,
                  mirror: segment.mirror,
                ))
            .toList(),
        history: history,
        durationMs: totalDurationMs,
        createdAtMs: now.millisecondsSinceEpoch,
        projectId: ref.read(projectProvider).activeProjectId,
      );

      await VideoProcessingTaskHandler.enqueueJob(job);
      await _startForegroundService();

      state = state.copyWith(
        videoSegments: [],
        videoSequenceDir: null,
      );
      _videoDataHistory.clear();
      _recordingStartTime = null;
    } catch (e) {
      debugPrint("Stop recording error: $e");
      final friendlyError = _friendlyStopRecordingError(e);
      state = state.copyWith(
        isRecording: false,
        clearProcessingProgress: true,
        videoSegments: [],
        videoSequenceDir: null,
        processingMessage: 'Video recording failed.',
        videoProcessingError: friendlyError,
      );
      _videoHistoryTimer?.cancel();
      _videoHistoryTimer = null;
      _videoDataHistory.clear();
      _recordingStartTime = null;
      await FlutterForegroundTask.stopService();
      if (_isNativeCameraNullPointer(e)) {
        unawaited(refreshCamera());
      }
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Video recording failed: $friendlyError"),
          ),
        );
      }
    } finally {
      _stopRecordingInFlight = false;
    }
  }

  Future<void> _startForegroundService() async {
    // 0. Ensure notification permission
    await PermissionService.requestNotificationPermission();

    // 1. Core initialization is now in main.dart to ensure it's called early and once.

    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'SurveyCam - Media processing',
        notificationText: 'Preparing media...',
        callback: startCallback,
      );
    } else {
      await FlutterForegroundTask.startService(
        notificationTitle: 'SurveyCam - Media processing',
        notificationText: 'Preparing media...',
        callback: startCallback,
      );
    }
  }

  Future<void> _resumePendingVideoProcessing() async {
    try {
      final previousFailure =
          await VideoProcessingTaskHandler.takeLastFailure();
      if (previousFailure != null) {
        state = state.copyWith(
          clearProcessingProgress: true,
          processingMessage: 'Video processing failed.',
          videoProcessingError: _friendlyVideoError(previousFailure),
        );
      }

      final previousImageFailure =
          await VideoProcessingTaskHandler.takeLastImageFailure();
      if (previousImageFailure != null) {
        debugPrint('Pending photo save failed: $previousImageFailure');
      }

      if (await VideoProcessingTaskHandler.hasPendingJob()) {
        state = state.copyWith(
          processingProgress: 0.05,
          processingMessage: 'Resuming video processing...',
          videoProcessingError: null,
        );
        await _startForegroundService();
      } else if (await VideoProcessingTaskHandler.hasPendingImageJob()) {
        await _startForegroundService();
      }
    } catch (e) {
      debugPrint('Pending video resume skipped: $e');
    }
  }

  // ================= DISPOSE =================

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoHistoryTimer?.cancel();
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    ref.read(cameraRepositoryProvider).dispose();
    super.dispose();
  }
}
