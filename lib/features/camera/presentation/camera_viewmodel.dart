import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:surveycam/core/di/providers.dart';
import 'package:surveycam/core/permissions/permission_service.dart';
import 'package:surveycam/core/utils/device_orientation_provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:surveycam/core/services/background_video_task.dart';
import 'package:surveycam/core/utils/gallery_saver.dart';
import 'package:surveycam/core/utils/thumbnail_utils.dart';
import 'package:surveycam/features/camera/data/CameraState.dart';
import 'package:surveycam/features/camera/domain/camera_lens_type.dart';
import 'package:surveycam/features/overlay/presentation/overlay_settings_provider.dart';
import 'package:surveycam/features/gallery/presentation/image_preview_screen.dart';
import 'package:surveycam/features/gallery/presentation/last_image_provider.dart';
import 'package:surveycam/features/location/presentation/location_viewmodel.dart';
import 'package:surveycam/features/overlay/presentation/captured_overlay_provider.dart';
import 'package:surveycam/features/overlay/presentation/overlay_preview_state.dart';
import 'package:surveycam/features/gallery/data/sitesnap_gallery_repository.dart';
import 'package:surveycam/features/overlay/domain/video_overlay_sample.dart';

import '../../overlay/presentation/video_watermark_processor.dart';

final cameraViewModelProvider =
    StateNotifierProvider<CameraViewModel, CameraState>((ref) {
  return CameraViewModel(ref);
});

class CameraViewModel extends StateNotifier<CameraState>
    with WidgetsBindingObserver {
  final Ref ref;

  double _currentExposure = 0.0;
  double _minExposure = 0.0;
  double _maxExposure = 0.0;

  bool _isCameraStable = false;
  bool _isInitializing = false;
  bool _isDisposing = false;
  bool _isRestarting = false;
  Timer? _videoHistoryTimer;
  ReceivePort? _receivePort;

  // Optimized overlay history storage
  final List<VideoOverlaySample> _videoDataHistory = [];
  DateTime? _recordingStartTime;

  bool get isCameraStable => _isCameraStable;
  double get exposureValue => _currentExposure;

  CameraViewModel(this.ref) : super(const CameraState(isReady: false)) {
    WidgetsBinding.instance.addObserver(this);
    _initBackgroundService();
    // Removed automatic initialize() to allow manual/early trigger
  }

  void _initBackgroundService() {
    _receivePort?.close();
    _receivePort = FlutterForegroundTask.receivePort;
    _receivePort?.listen(_onReceiveTaskData);
  }

  void _onReceiveTaskData(dynamic message) {
    if (message is Map<String, dynamic>) {
      if (message['type'] == 'progress') {
        state = state.copyWith(processingProgress: message['value']);
      } else if (message['type'] == 'complete') {
        state = state.copyWith(clearProcessingProgress: true);
        ref.invalidate(galleryFilesProvider);
      } else if (message['type'] == 'error') {
        state = state.copyWith(
            clearProcessingProgress: true, error: message['error']);
      }
    }
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

      // Set to auto focus and exposure by default in parallel
      if (controller.value.isInitialized) {
        await Future.wait([
          controller
              .setFocusMode(FocusMode.auto)
              .catchError((e) => debugPrint("Initial focus mode error: $e")),
          controller
              .setExposureMode(ExposureMode.auto)
              .catchError((e) => debugPrint("Initial exposure mode error: $e")),
          controller
              .setFlashMode(FlashMode.off)
              .catchError((e) => debugPrint("Initial flash mode error: $e")),
          controller
              .setFocusPoint(const Offset(0.5, 0.5))
              .catchError((e) => debugPrint("Initial focus point error: $e")),
          controller.setExposurePoint(const Offset(0.5, 0.5)).catchError(
              (e) => debugPrint("Initial exposure point error: $e")),
        ]);
      }

      if (controller.value.isInitialized) {
        // Fetch capabilities in parallel
        final caps = await Future.wait([
          controller.getMinExposureOffset(),
          controller.getMaxExposureOffset(),
          controller.getMinZoomLevel(),
          controller.getMaxZoomLevel(),
        ]);

        _minExposure = caps[0];
        _maxExposure = caps[1];
        final minZoom = caps[2];
        final maxZoom = caps[3];

        // Set exposure offset to 0.0 (Neutral) to minimize ISO noise in low light
        _currentExposure = 0.0.clamp(_minExposure, _maxExposure);

        try {
          await controller.setExposureOffset(_currentExposure);
        } catch (e) {
          debugPrint("Initial exposure offset error: $e");
        }

        _isCameraStable = true;

        state = state.copyWith(
          isReady: true,
          controller: controller,
          exposure: _currentExposure,
          minExposure: _minExposure,
          maxExposure: _maxExposure,
          zoom: 1.0,
          minZoom: minZoom,
          maxZoom: maxZoom,
          error: null,
        );
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

  Future<void> _warmUpAfterCameraReady() async {
    try {
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
    }
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
                  this.state.copyWith(controller: null, isReady: false);
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
          debugPrint("Camera preview resumed instantly.");
        } catch (e) {
          debugPrint("Instant resume failed: $e. Re-initializing...");
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
    state = state.copyWith(controller: null, isReady: false, error: null);
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
        final segment = VideoSegment(path: segmentFile.path, lens: state.currentLens);
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

    state = state.copyWith(currentLens: nextLens, isReady: false);

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

  Future<String?> capture() async {
    final controller = state.controller;

    if (!state.isReady ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        state.isCapturing ||
        state.isRecording ||
        (state.processingProgress != null)) {
      // HEALTH CHECK: If we think we are ready but controller is null or not init, trigger recovery
      if (state.isReady &&
          (controller == null || !controller.value.isInitialized)) {
        debugPrint(
            "Camera state desync detected during capture. Triggering recovery...");
        await refreshCamera();
      }

      return null;
    }

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

      // 1. Prepare hardware (Parallelized)
      if (controller.value.isInitialized) {
        await Future.wait([
          controller.setFocusMode(FocusMode.auto).catchError((e) => debugPrint("Capture focus mode error: $e")),
          controller.setExposureMode(ExposureMode.auto).catchError((e) => debugPrint("Capture exposure mode error: $e")),
          controller.setExposurePoint(const Offset(0.5, 0.5)).catchError((e) => debugPrint("Capture exposure point error: $e")),
        ]);
      }

      // 2. Enable Light for Capture
      if (state.flashMode == FlashMode.always) {
        if (state.currentLens == CameraLensType.front) {
          // For front camera, we use the Screen Flash (UI based)
          // Reduced delay for front flash stabilization
          await Future.delayed(const Duration(milliseconds: 80));
        } else {
          // For back camera, use the physical LED
          await controller.setFlashMode(FlashMode.torch);
          // Reduced delay for back flash stabilization (250ms -> 100ms)
          await Future.delayed(const Duration(milliseconds: 100));
        }
      } else {
        await controller.setFlashMode(FlashMode.off);
      }

      // 2.5 LOCK Focus and Exposure for full clarity (Parallelized)
      if (controller.value.isInitialized) {
        await Future.wait([
          controller.setFocusMode(FocusMode.locked).catchError((e) => debugPrint("Locking focus error: $e")),
          controller.setExposureMode(ExposureMode.locked).catchError((e) => debugPrint("Locking exposure error: $e")),
        ]);
      }

      // 3. CAPTURE
      final path = await repo.takePicture();

      // 4. CLEANUP (Non-blocking)
      if (state.flashMode == FlashMode.always) {
        unawaited(_nuclearFlashKill(controller));
      } else {
        unawaited(_softFlashQuench(controller));
      }

      unawaited(HapticFeedback.lightImpact());
      return path;
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
      _restoreCameraState(controller);
      state = state.copyWith(isCapturing: false);
    }
  }

  Future<void> _restoreCameraState(CameraController? controller) async {
    try {
      if (controller != null && controller.value.isInitialized) {
        await controller.setFlashMode(FlashMode.off);
        await Future.wait([
          controller.setFocusMode(FocusMode.auto),
          controller.setExposureMode(ExposureMode.auto),
          controller.setExposureOffset(_currentExposure),
        ]);
        await controller.resumePreview();
      }
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

      final deviceOrientation = ref.read(deviceOrientationProvider);

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
        unawaited(result.then((savedFile) {
          if (savedFile != null) {
            ref.read(lastImageProvider.notifier).state = savedFile;
            ref.invalidate(galleryFilesProvider);
          }
        }));
      } else if (result is File) {
        ref.read(lastImageProvider.notifier).state = result;
        ref.invalidate(galleryFilesProvider);
      } else if (result != null) {
        ref.read(lastImageProvider.notifier).state = originalFile;
        ref.invalidate(galleryFilesProvider);
      }
    } catch (e) {
      debugPrint("Post capture error: $e");
    }
  }

  Future<void> startVideoRecording({bool clearSegments = false}) async {
    final controller = state.controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        state.isRecording ||
        (state.processingProgress != null)) {
      return;
    }

    try {
      final repo = ref.read(cameraRepositoryProvider);

      if (state.flashMode == FlashMode.always &&
          state.currentLens != CameraLensType.front) {
        await controller.setFlashMode(FlashMode.torch);
      }

      await repo.startVideoRecording();

      // Start history tracking
      _videoHistoryTimer?.cancel();
      if (clearSegments) {
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
        final currentOverlay = ref.read(overlayPreviewProvider);
        final currentOrientation = state.orientation;
        final currentSettings = ref.read(overlaySettingsProvider);
        final timestamp =
            DateTime.now().difference(_recordingStartTime!).inMilliseconds;

        _videoDataHistory.add(VideoOverlaySample(
          data: currentOverlay,
          orientation: currentOrientation,
          settings: currentSettings,
          timestampMs: timestamp,
        ));
      });

      // Initial sample
      _videoDataHistory.add(VideoOverlaySample(
        data: ref.read(overlayPreviewProvider),
        orientation: state.orientation,
        settings: ref.read(overlaySettingsProvider),
        timestampMs: 0,
      ));

      state = state.copyWith(
        isRecording: true,
        videoSegments: clearSegments ? <VideoSegment>[] : state.videoSegments,
      );
      unawaited(HapticFeedback.heavyImpact());
    } catch (e) {
      debugPrint("Start recording error: $e");
    }
  }

  Future<void> stopVideoRecording(BuildContext context) async {
    final controller = state.controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        !state.isRecording) {
      return;
    }

    try {
      final repo = ref.read(cameraRepositoryProvider);
      _videoHistoryTimer?.cancel();
      _videoHistoryTimer = null;

      final lastSegmentFile = await repo.stopVideoRecording();
      final lastSegment = VideoSegment(path: lastSegmentFile.path, lens: state.currentLens);
      final allSegments = [...state.videoSegments, lastSegment];
      final totalDurationMs =
          DateTime.now().difference(_recordingStartTime!).inMilliseconds;

      // Capture data needed for processing before clearing local state
      final history = List<VideoOverlaySample>.from(_videoDataHistory);

      // Update state: stop recording and start processing overlay
      state = state.copyWith(
        isRecording: false,
        processingProgress: 0.05,
      );
      unawaited(HapticFeedback.mediumImpact());

      if (state.flashMode == FlashMode.always) {
        await _softFlashQuench(controller);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Processing video..."),
            duration: Duration(milliseconds: 1500),
          ),
        );
      }

      // 1. Merge segments and Apply Mirroring (hflip) where necessary
      String finalVideoPath = lastSegment.path;
      final bool hasFrontCamera = allSegments.any((s) => s.lens == CameraLensType.front);

      if (allSegments.length > 1 || hasFrontCamera) {
        debugPrint("Merging/Processing ${allSegments.length} segments...");
        final mergedPath = await VideoWatermarkProcessor.mergeVideos(
          allSegments.map((s) => s.path).toList(),
          mirrorMap: allSegments.map((s) => s.lens == CameraLensType.front).toList(),
        );
        if (mergedPath != null) {
          finalVideoPath = mergedPath;
          debugPrint("Merged video saved at: $finalVideoPath");
        } else {
          debugPrint("Merging failed, using last segment.");
        }
      }

      // 2. Start foreground service
      await _startForegroundService();

      // 3. Orchestrate processing on main isolate
      unawaited(_processVideoOnMainIsolate(
        videoPath: finalVideoPath,
        history: history,
        durationMs: totalDurationMs,
      ));

      // 4. Cleanup local segments state
      state = state.copyWith(
        videoSegments: [],
        videoSequenceDir: null,
      );
      _videoDataHistory.clear();
    } catch (e) {
      debugPrint("Stop recording error: $e");
      state = state.copyWith(isRecording: false, clearProcessingProgress: true);
      await FlutterForegroundTask.stopService();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving video: $e")),
        );
      }
    }
  }

  Future<void> _startForegroundService() async {
    // 0. Ensure notification permission
    await PermissionService.requestNotificationPermission();

    // 1. Initialize notification options
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'processing_channel',
        channelName: 'Video Processing',
        channelDescription: 'Shows progress of video watermarking',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    // 2. Start service
    await FlutterForegroundTask.startService(
      notificationTitle: 'SurveyCam',
      notificationText: 'Preparing video watermark...',
      callback: startCallback,
    );
  }

  Future<void> _processVideoOnMainIsolate({
    required String videoPath,
    required List<VideoOverlaySample> history,
    required int durationMs,
  }) async {
    try {
      // 1. Generate Overlay Sequence
      _updateNotification("Generating watermark frames...");
      
      // OPTIMIZATION: Small delay to let UI update before heavy sequence generation
      await Future.delayed(const Duration(milliseconds: 100));

      final sequenceDir =
          await VideoWatermarkProcessor.generateVideoOverlaySequence(
        samples: history,
        width: 1080,
        height: 1920,
        onProgress: (p) {
          final progress = 0.1 + (p * 0.3); // 10% to 40%
          state = state.copyWith(processingProgress: progress);
        },
      );

      if (sequenceDir == null) {
        throw Exception("Failed to generate overlay sequence");
      }

      // 2. Apply Sequence (Heavy FFmpeg part)
      final processedPath =
          await VideoWatermarkProcessor.applyOverlaySequenceToVideo(
        videoPath: videoPath,
        sequenceDir: sequenceDir,
        frameCount: history.length,
        durationMs: durationMs,
        onProgress: (p) {
          final progress = 0.4 + (p * 0.5); // 40% to 90%
          state = state.copyWith(processingProgress: progress);
          _updateNotification(
              "Applying watermark... ${(progress * 100).toInt()}%");
        },
      );

      if (processedPath == null) throw Exception("FFmpeg processing failed");

      state = state.copyWith(processingProgress: 0.95);
      _updateNotification("Saving to gallery... 95%");

      // 3. Save to Gallery
      final savedPath = await GallerySaver.saveVideo(processedPath);
      await ThumbnailUtils.generateVideoThumbnail(savedPath);

      _updateNotification("Video saved successfully!", isFinished: true);

      state = state.copyWith(clearProcessingProgress: true);
      ref.invalidate(galleryFilesProvider);
    } catch (e) {
      debugPrint("Process video on main isolate error: $e");
      _updateNotification("Error: ${e.toString()}", isFinished: true);
      state =
          state.copyWith(clearProcessingProgress: true, error: e.toString());
    } finally {
      // Stop service after a delay to show success/error
      Future.delayed(const Duration(seconds: 3), () {
        FlutterForegroundTask.stopService();
      });
    }
  }

  void _updateNotification(String text, {bool isFinished = false}) {
    FlutterForegroundTask.updateService(
      notificationTitle: "SurveyCam - Processing",
      notificationText: text,
    );
  }


  // ================= DISPOSE =================

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoHistoryTimer?.cancel();
    _receivePort?.close();
    ref.read(cameraRepositoryProvider).dispose();
    super.dispose();
  }
}
