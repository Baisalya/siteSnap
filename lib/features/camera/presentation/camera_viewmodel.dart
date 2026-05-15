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
import 'package:surveycam/features/gallery/presentation/image_preview_screen.dart';
import 'package:surveycam/features/gallery/presentation/last_image_provider.dart';
import 'package:surveycam/features/location/presentation/location_viewmodel.dart';
import 'package:surveycam/features/overlay/presentation/captured_overlay_provider.dart';
import 'package:surveycam/features/overlay/presentation/overlay_preview_state.dart';
import 'package:surveycam/features/gallery/data/sitesnap_gallery_repository.dart';

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

  bool get isCameraStable => _isCameraStable;
  double get exposureValue => _currentExposure;

  CameraViewModel(this.ref)
      : super( const CameraState(isReady: false)) {
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
        state = state.copyWith(clearProcessingProgress: true, error: message['error']);
      }
    }
  }

  // ================= INIT =================

  Future<void> initialize() async {
    if (_isInitializing || _isDisposing) return;
    _isInitializing = true;

    state = state.copyWith(error: null);

    try {
      // Parallelize permission check and repository preparation
      await Future.wait([
        PermissionService.requestCameraAndLocation(),
        Future.microtask(() => ref.invalidate(locationStreamProvider)),
      ]);

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
        state = state.copyWith(isReady: false, error: "Camera controller failed to initialize");
        return;
      }

      // Ensure the controller is initialized before proceeding
      if (!controller.value.isInitialized) {
        await controller.initialize();
      }

      // Set to auto focus and exposure by default in parallel
      if (controller.value.isInitialized) {
        await Future.wait([
          controller.setFocusMode(FocusMode.auto).catchError((e) => debugPrint("Initial focus mode error: $e")),
          controller.setExposureMode(ExposureMode.auto).catchError((e) => debugPrint("Initial exposure mode error: $e")),
          controller.setFlashMode(FlashMode.off).catchError((e) => debugPrint("Initial flash mode error: $e")),
          controller.setFocusPoint(const Offset(0.5, 0.5)).catchError((e) => debugPrint("Initial focus point error: $e")),
          controller.setExposurePoint(const Offset(0.5, 0.5)).catchError((e) => debugPrint("Initial exposure point error: $e")),
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
      } else {
        state = state.copyWith(isReady: false, error: "Camera controller not initialized after setup");
      }

    } catch (e) {
      debugPrint('Init error: $e');
      String errorMessage = e.toString();
      if (errorMessage.contains('CameraException')) {
        errorMessage = "Camera Error: Please ensure no other app is using the camera.";
      }
      state = state.copyWith(isReady: false, error: errorMessage);
    } finally {
      _isInitializing = false;
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
          
          if (appState == AppLifecycleState.paused || appState == AppLifecycleState.hidden) {
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
              this.state = this.state.copyWith(controller: null, isReady: false);
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

  Future<void> setFocusPoint(
      Offset position, Size previewSize) async {
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
          (_currentExposure + delta)
              .clamp(_minExposure, _maxExposure);

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
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (_) {}
  }

  /// The heavy-duty reset for stuck drivers (causes a brief flicker)
  Future<void> _nuclearFlashKill(CameraController controller) async {
    try {
      if (!controller.value.isInitialized) return;

      await controller.setFlashMode(FlashMode.off);
      await Future.delayed(const Duration(milliseconds: 100));

      // Torch "kick" to reset the hardware driver
      await controller.setFlashMode(FlashMode.torch);
      await Future.delayed(const Duration(milliseconds: 150));
      await controller.setFlashMode(FlashMode.off);
      
      // Cooldown to let sensor recover from the burst
      await Future.delayed(const Duration(milliseconds: 200));
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
        // Just set to off, no nuclear kill needed here as it causes a flicker
        await controller.setFlashMode(FlashMode.off);
      } else {
        // When user selects ON, we keep the controller's flash OFF for now
        // and only enable it during the actual capture to prevent "sticking"
        await controller.setFlashMode(FlashMode.off);
      }
    } catch (e) {
      debugPrint("Error setting flash mode: $e");
    }
  }

  Future<void> cycleFlashMode() async {
    final nextMode = state.flashMode == FlashMode.off ? FlashMode.always : FlashMode.off;
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
        final segment = await repo.stopVideoRecording();
        state = state.copyWith(
          videoSegments: [...state.videoSegments, segment],
          isRecording: false,
        );
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
          state = state.copyWith(isReady: true, controller: controller, error: null);
        }

        if (wasRecording) {
          await startVideoRecording();
        }
      }
    } catch (e) {
      debugPrint("Switch camera error: $e");
      state = state.copyWith(isReady: false, error: e.toString(), isRecording: false);
    }
  }

  // ================= CAPTURE =================

  void setCameraMode(CameraMode mode) {
    state = state.copyWith(cameraMode: mode);
  }

  Future<void> capture(BuildContext context) async {
    final controller = state.controller;

    if (!state.isReady ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        state.isCapturing ||
        state.isRecording) {
      
      // HEALTH CHECK: If we think we are ready but controller is null or not init, trigger recovery
      if (state.isReady && (controller == null || !controller.value.isInitialized)) {
        debugPrint("Camera state desync detected during capture. Triggering recovery...");
        await refreshCamera();
      }

      if (state.isRecording) {
        await stopVideoRecording(context);
      }
      return;
    }

    if (state.cameraMode == CameraMode.video) {
      await startVideoRecording(clearSegments: true);
      return;
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

      // 1. Prepare hardware
      if (controller.value.isInitialized) {
        try {
          await controller.setFocusMode(FocusMode.auto);
        } catch (e) {
          debugPrint("Capture focus mode error: $e");
        }
        
        try {
          await controller.setExposureMode(ExposureMode.auto);
        } catch (e) {
          debugPrint("Capture exposure mode error: $e");
        }
        
        // Re-trigger metering on the center point to maximize gain
        try {
          await controller.setExposurePoint(const Offset(0.5, 0.5));
        } catch (e) {
          debugPrint("Capture exposure point error: $e");
        }
      }

      // 2. Enable Light for Capture
      if (state.flashMode == FlashMode.always) {
        if (state.currentLens == CameraLensType.front) {
          // For front camera, we use the Screen Flash (UI based)
          // We wait a moment for the screen to turn bright white in the UI
          await Future.delayed(const Duration(milliseconds: 300));
        } else {
          // For back camera, use the physical LED
          await controller.setFlashMode(FlashMode.torch);
          await Future.delayed(const Duration(milliseconds: 600)); // Increased for stabilization
        }
      } else {
        await controller.setFlashMode(FlashMode.off);
        // Wait longer for AE to stabilize for high clarity and low noise
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 2.5 LOCK Focus and Exposure for full clarity
      try {
        if (controller.value.isInitialized) {
          await controller.setFocusMode(FocusMode.locked);
          await controller.setExposureMode(ExposureMode.locked);
        }
      } catch (e) {
        debugPrint("Locking focus/exposure error: $e");
      }

      // 3. CAPTURE
      final path = await repo.takePicture();

      // 4. IMMEDIATE CLEANUP
      // Give the hardware a tiny breath to finalize the file write
      await Future.delayed(const Duration(milliseconds: 200));

      if (state.flashMode == FlashMode.always) {
        await _nuclearFlashKill(controller);
      } else {
        await _softFlashQuench(controller);
      }

      unawaited(HapticFeedback.lightImpact());
      if (context.mounted) {
        await _handlePostCapture(path, context, deviceOrientation);
      }

    } catch (e) {
      debugPrint('Capture error: $e');
      // BULLETPROOF: If a camera exception happens, try to refresh/recover automatically
      if (e.toString().contains('CameraException')) {
        debugPrint("Critical camera exception during capture. Attempting automatic recovery...");
        await refreshCamera();
      }
    } finally {
      // 🔓 RESTORATION
      try {
        if (controller.value.isInitialized) {
          // IMPORTANT: Keep controller flash OFF during preview to prevent sticking.
          await controller.setFlashMode(FlashMode.off);
          
          await controller.setFocusMode(FocusMode.auto);
          await controller.setExposureMode(ExposureMode.auto);
          await controller.setExposureOffset(_currentExposure);

          // Kick the pipeline to ensure it's not hung
          await controller.resumePreview();
          
          // Extra stabilization delay before allowing the next capture
          await Future.delayed(const Duration(milliseconds: 400));
        }
      } catch (e) {
        debugPrint("Restoration error: $e");
      }
      state = state.copyWith(isCapturing: false);
    }
  }

  Future<void> startVideoRecording({bool clearSegments = false}) async {
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized || state.isRecording) return;

    try {
      final repo = ref.read(cameraRepositoryProvider);
      
      if (state.flashMode == FlashMode.always && state.currentLens != CameraLensType.front) {
        await controller.setFlashMode(FlashMode.torch);
      }

      await repo.startVideoRecording();
      
      // Start history tracking
      _videoHistoryTimer?.cancel();
      _videoHistoryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final currentOverlay = ref.read(overlayPreviewProvider);
        state = state.copyWith(
          videoDataHistory: [...state.videoDataHistory, currentOverlay],
        );
      });
      // Initial sample
      final initialOverlay = ref.read(overlayPreviewProvider);
      state = state.copyWith(
        isRecording: true,
        videoSegments: clearSegments ? [] : state.videoSegments,
        videoDataHistory: clearSegments ? [initialOverlay] : [...state.videoDataHistory, initialOverlay],
      );
      unawaited(HapticFeedback.heavyImpact());
    } catch (e) {
      debugPrint("Start recording error: $e");
    }
  }

  Future<void> stopVideoRecording(BuildContext context) async {
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized || !state.isRecording) return;

    try {
      final repo = ref.read(cameraRepositoryProvider);
      _videoHistoryTimer?.cancel();
      _videoHistoryTimer = null;
      
      final lastSegment = await repo.stopVideoRecording();
      final allSegments = [...state.videoSegments, lastSegment];
      
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

      // 1. Merge segments if necessary
      String finalVideoPath = lastSegment.path;
      if (allSegments.length > 1) {
        debugPrint("Merging ${allSegments.length} segments...");
        final mergedPath = await VideoWatermarkProcessor.mergeVideos(
          allSegments.map((s) => s.path).toList(),
        );
        if (mergedPath != null) {
          finalVideoPath = mergedPath;
          debugPrint("Merged video saved at: $finalVideoPath");
        } else {
          debugPrint("Merging failed, using last segment.");
        }
      }

      // 2. Generate overlay sequence (Main Isolate)
      final sequenceDir = await VideoWatermarkProcessor.generateVideoOverlaySequence(
        history: state.videoDataHistory,
        orientation: state.orientation,
        width: 1080,
        height: 1920,
        onProgress: (p) {
          state = state.copyWith(processingProgress: 0.05 + (p * 0.35)); // 5% to 40%
        },
      );

      if (sequenceDir == null) {
        throw Exception("Failed to generate overlay sequence.");
      }

      // 3. Start foreground service to keep app alive and show notification
      await _startForegroundService();

      // 4. Orchestrate processing on main isolate (avoids MissingPluginException)
      unawaited(_processVideoOnMainIsolate(
        videoPath: finalVideoPath,
        sequenceDir: sequenceDir,
        frameCount: state.videoDataHistory.length,
      ));

      // 5. Cleanup local segments state
      state = state.copyWith(
        videoSegments: [], 
        videoDataHistory: [], 
      );

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
    required String sequenceDir,
    required int frameCount,
  }) async {
    try {
      // 1. Apply Sequence (Heavy FFmpeg part)
      final processedPath = await VideoWatermarkProcessor.applyOverlaySequenceToVideo(
        videoPath: videoPath,
        sequenceDir: sequenceDir,
        frameCount: frameCount,
        onProgress: (p) {
          final progress = 0.4 + (p * 0.5); // 40% to 90%
          state = state.copyWith(processingProgress: progress);
          _updateNotification("Applying watermark... ${(progress * 100).toInt()}%");
        },
      );

      if (processedPath == null) throw Exception("FFmpeg processing failed");

      state = state.copyWith(processingProgress: 0.95);
      _updateNotification("Saving to gallery... 95%");

      // 2. Save to Gallery
      final savedPath = await GallerySaver.saveVideo(processedPath);
      await ThumbnailUtils.generateVideoThumbnail(savedPath);

      _updateNotification("Video saved successfully!", isFinished: true);
      
      state = state.copyWith(clearProcessingProgress: true);
      ref.invalidate(galleryFilesProvider);

    } catch (e) {
      debugPrint("Process video on main isolate error: $e");
      _updateNotification("Error: ${e.toString()}", isFinished: true);
      state = state.copyWith(clearProcessingProgress: true, error: e.toString());
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

  Future<void> _handlePostCapture(
      String path,
      BuildContext context,
      DeviceOrientation orientation,
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

      if (result != null) {
        ref.read(lastImageProvider.notifier).state = originalFile;
        ref.invalidate(galleryFilesProvider);
      }
    } catch (e) {
      debugPrint("Post capture error: $e");
    }
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
