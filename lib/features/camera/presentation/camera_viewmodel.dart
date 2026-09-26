import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart' hide CameraLensType;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:surveycam/core/di/providers.dart';
import 'package:surveycam/core/permissions/permission_service.dart';
import 'package:surveycam/core/monetization/rewarded_capture_access.dart';
import 'package:surveycam/core/utils/device_orientation_provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:surveycam/core/services/app_exit_info_service.dart';
import 'package:surveycam/core/services/background_video_task.dart';
import 'package:surveycam/core/services/media_audit_service.dart';
import 'package:surveycam/core/services/recording_storage_guard.dart';
import 'package:surveycam/core/services/video_processing_job.dart';
import 'package:surveycam/core/utils/gallery_saver.dart';
import 'package:surveycam/core/utils/thumbnail_utils.dart';
import 'package:surveycam/features/camera/application/latest_value_coalescer.dart';
import 'package:surveycam/features/camera/application/camera_session_queue.dart';
import 'package:surveycam/features/camera/application/recording_session_coordinator.dart';
import 'package:surveycam/features/camera/data/CameraState.dart';
import 'package:surveycam/features/camera/domain/camera_lens_type.dart';
import 'package:surveycam/features/camera/domain/video_recording_session.dart';
import 'package:surveycam/features/camera/domain/video_capture_orientation.dart';
import 'package:surveycam/features/camera/domain/video_recording_backend.dart';
import 'package:surveycam/features/camera/domain/video_recording_production_gate.dart';
import 'package:surveycam/features/camera/presentation/camera_settings_provider.dart';
import 'package:surveycam/features/overlay/presentation/overlay_settings_provider.dart';
import 'package:surveycam/features/gallery/presentation/image_preview_screen.dart';
import 'package:surveycam/features/gallery/presentation/last_image_provider.dart';
import 'package:surveycam/features/location/presentation/location_viewmodel.dart';
import 'package:surveycam/features/overlay/domain/overlay_model.dart';
import 'package:surveycam/features/overlay/domain/overlay_render_snapshot.dart';
import 'package:surveycam/features/overlay/presentation/overlay_render_snapshot_provider.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';
import 'package:surveycam/features/overlay/presentation/captured_overlay_provider.dart';
import 'package:surveycam/features/overlay/presentation/overlay_preview_state.dart';
import 'package:surveycam/features/overlay/presentation/overlay_viewmodel.dart';
import 'package:surveycam/features/gallery/data/sitesnap_gallery_repository.dart';
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

  bool get photoBlockedByRewardedVideo =>
      state.isRecording && _recordingUsesRewardedFeatures;

  double _currentExposure = 0.0;
  double _minExposure = 0.0;
  double _maxExposure = 0.0;
  final LatestValueCoalescer<double> _exposureUpdates =
      LatestValueCoalescer<double>();
  CameraController? _exposureController;
  double? _lastSubmittedExposure;

  bool _isCameraStable = false;
  bool _isInitializing = false;
  bool _isDisposing = false;
  bool _isRestarting = false;
  bool _captureInFlight = false;
  bool _recordingUsesRewardedFeatures = false;
  bool _startRecordingInFlight = false;
  bool _stopRecordingInFlight = false;
  int _pendingStopRequests = 0;
  bool _nativeRecordingStarted = false;
  int _realtimeActivationToken = 0;
  CameraController? _zoomController;
  double? _lastSubmittedZoom;
  double? _pendingZoom;
  int? _zoomFrameCallbackId;
  int _zoomDriveGeneration = 0;
  bool _currentRecordingUsesNativeFrontMirror = false;
  // Frozen for the whole logical recording. PHOTO/preview orientation remains
  // owned by the existing deviceOrientationProvider and is never rewritten by
  // video code. Locking the encoded axis prevents portrait/landscape segment
  // churn, frame squashing, and CameraX restart races mid-recording.
  DeviceOrientation? _recordingCaptureOrientation;
  bool _zoomGestureActive = false;
  int _zoomAnimationGeneration = 0;

  // App lifecycle events can arrive as inactive -> paused -> resumed in quick
  // succession. Keep them serialized so CameraPreview never receives a
  // controller while the repository is disposing the same native session.
  Future<void> _lifecycleQueue = Future<void>.value();
  final CameraSessionQueue _sessionQueue = CameraSessionQueue();
  int _lifecycleGeneration = 0;
  AppLifecycleState _latestLifecycleState = AppLifecycleState.resumed;

  final RecordingSessionCoordinator _recordingSession =
      RecordingSessionCoordinator();

  bool get isCameraStable => _isCameraStable;
  double get exposureValue => _currentExposure;

  CameraViewModel(this.ref) : super(const CameraState(isReady: false)) {
    WidgetsBinding.instance.addObserver(this);
    // Start plugin/preferences initialization while CameraX is opening so the
    // first shutter press does not pay these one-time costs.
    unawaited(_warmCaptureDependencies());
    ref.listen<OverlayData>(
      overlayPreviewProvider,
      (_, __) => _recordCurrentVideoOverlaySample(),
    );
    ref.listen<OverlaySettings>(
      effectiveOverlaySettingsProvider,
      (_, __) => _recordCurrentVideoOverlaySample(),
    );

    // Defer initialization work to avoid blocking the main thread during constructor execution (ANR prevention)
    Future.microtask(() {
      if (mounted) {
        _initBackgroundService();
      }
    });
    // Removed automatic initialize() to allow manual/early trigger
  }

  void _initBackgroundService() {
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
  }

  Future<void> _warmCaptureDependencies() async {
    try {
      await Future.wait<void>([
        ref.read(overlaySettingsProvider.notifier).ready,
        ref.read(projectProvider.notifier).ready,
        GallerySaver.warmUp(),
      ]);
    } catch (e) {
      // Capture can still continue with provider defaults. Individual save
      // paths retain their own error handling and persistence fallbacks.
      debugPrint('Photo dependency warm-up skipped: $e');
    }
  }

  void _onReceiveTaskData(dynamic message) {
    if (!mounted) return;
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
        unawaited(_syncCompletedVideo(message));
      } else if (message['type'] == 'image_complete') {
        unawaited(_syncCompletedImage(message));
      } else if (message['type'] == 'image_error') {
        final originalPath = message['originalPath'] as String?;
        if (originalPath != null && originalPath.isNotEmpty) {
          ref.read(rewardedCaptureAccessProvider).failBackgroundImage(
                originalPath,
              );
          ref.read(galleryProcessingProvider.notifier).fail(File(originalPath));
        }
      } else if (message['type'] == 'error') {
        state = state.copyWith(
          clearProcessingProgress: true,
          processingMessage: 'Video processing failed.',
          videoProcessingError: _friendlyVideoError(message['error']),
        );
      } else if (message['type'] == 'cancelled') {
        final jobId = message['jobId'] as String?;
        if (jobId != null) {
          ref.read(rewardedCaptureAccessProvider).failVideo(jobId);
        }
        state = state.copyWith(
          clearProcessingProgress: true,
          processingMessage:
              message['message'] as String? ?? 'Processing cancelled.',
          videoProcessingError: null,
        );
      }
    }
  }

  Future<void> _syncCompletedVideo(Map<String, dynamic> message) async {
    final jobId = message['jobId'] as String?;
    final projectId = message['projectId'] as String?;
    final rawPaths = message['paths'];
    final paths = rawPaths is List
        ? rawPaths.whereType<String>().where((path) => path.isNotEmpty).toList()
        : <String>[];

    if (paths.isEmpty) {
      final singlePath = message['path'] as String?;
      if (singlePath != null && singlePath.isNotEmpty) {
        paths.add(singlePath);
      }
    }

    try {
      for (final path in paths) {
        await ref.read(projectProvider.notifier).assignFileToProject(
              File(path),
              projectId: projectId,
            );
      }
      if (paths.isEmpty) {
        await ref.read(projectProvider.notifier).refreshAssignments();
      }
      await ref.read(galleryFilesProvider.notifier).refresh();
    } finally {
      if (jobId != null) {
        await ref.read(rewardedCaptureAccessProvider).completeVideo(jobId);
      }
    }
  }

  Future<void> _syncCompletedImage(Map<String, dynamic> message) async {
    final originalPath = message['originalPath'] as String?;
    final savedPath = message['path'] as String?;
    final projectId = message['projectId'] as String?;
    if (savedPath == null || savedPath.isEmpty) {
      await ref.read(projectProvider.notifier).refreshAssignments();
      await ref.read(galleryFilesProvider.notifier).refresh();
      return;
    }

    final savedFile = File(savedPath);
    final originalFile = originalPath == null || originalPath.isEmpty
        ? null
        : File(originalPath);
    try {
      await ref.read(projectProvider.notifier).assignFileToProject(
            savedFile,
            projectId: projectId,
            replace: originalFile,
          );
    } finally {
      if (originalPath != null && originalPath.isNotEmpty) {
        await ref
            .read(rewardedCaptureAccessProvider)
            .completeBackgroundImage(originalPath);
      }
    }
    ref.read(lastImageProvider.notifier).state = savedFile;
    if (originalFile != null) {
      ref
          .read(galleryProcessingProvider.notifier)
          .complete(originalFile, savedFile);
      ref
          .read(galleryFilesProvider.notifier)
          .showFileImmediately(savedFile, replace: originalFile);
    } else {
      ref.read(galleryFilesProvider.notifier).showFileImmediately(savedFile);
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

  bool _isActiveController(CameraController controller) {
    return mounted &&
        state.controller == controller &&
        controller.value.isInitialized;
  }

  Future<void> _safeCameraCommand(
    CameraController controller,
    String label,
    Future<void> Function() command,
  ) async {
    if (!_isActiveController(controller)) return;

    try {
      await ref.read(cameraRepositoryProvider).runExclusive(() async {
        if (!_isActiveController(controller)) return;
        await command();
      });
    } catch (e) {
      debugPrint('Camera command skipped ($label): $e');
    }
  }

  Future<T?> _safeCameraQuery<T>(
    CameraController controller,
    String label,
    Future<T> Function() query,
  ) async {
    if (!_isActiveController(controller)) return null;

    try {
      return await ref.read(cameraRepositoryProvider).runExclusive(() async {
        if (!_isActiveController(controller)) return null;
        return await query();
      });
    } catch (e) {
      debugPrint('Camera query skipped ($label): $e');
      return null;
    }
  }

  // ================= INIT =================

  Future<void> initialize() async {
    if (_isInitializing || _isDisposing) return;
    ref.read(locationTrackingActiveProvider.notifier).state = true;
    _isInitializing = true;

    // If an old controller is still in state, hide the preview before the
    // repository gets a chance to health-check/dispose it. This prevents
    // CameraPreview.buildPreview() from being called on a disposed controller.
    if (state.controller != null || state.isReady) {
      state = state.copyWith(
        isReady: false,
        clearController: true,
        error: null,
      );
      await Future<void>.delayed(const Duration(milliseconds: 16));
    } else {
      state = state.copyWith(error: null);
    }

    try {
      await PermissionService.requestCameraAndMicrophone();

      if (!mounted || _isDisposing) return;

      // Arm the optional Android realtime compositor before CameraX binds
      // VideoCapture. The patched provider ignores photo-only bind groups, so
      // this has no OpenGL cost until the video use case is present.
      await ref.read(videoRecordingBackendProvider).armRealtimeOverlay();

      final repo = ref.read(cameraRepositoryProvider);
      final requestedLens = state.currentLens;

      try {
        await repo.initialize(requestedLens);
      } catch (e) {
        debugPrint('Repo init error: $e');
        // Try one retry if it fails immediately with a smaller delay. Bail out
        // if the app went to background while waiting.
        await Future.delayed(const Duration(milliseconds: 150));
        if (!mounted ||
            _isDisposing ||
            _latestLifecycleState != AppLifecycleState.resumed) {
          return;
        }
        await repo.initialize(requestedLens);
      }

      if (!mounted ||
          _isDisposing ||
          _latestLifecycleState != AppLifecycleState.resumed) {
        return;
      }

      final controller = repo.controller;
      if (controller == null) {
        state = state.copyWith(
          isReady: false,
          clearController: true,
          error: "Camera controller failed to initialize",
        );
        return;
      }

      // The repository owns controller.initialize(). Avoid a second initialize()
      // from the ViewModel because CameraX can crash when initialization overlaps
      // with lifecycle/dispose callbacks.
      if (controller.value.isInitialized) {
        _isCameraStable = true;

        state = state.copyWith(
          isReady: false,
          controller: controller,
          exposure: _currentExposure,
          minExposure: _minExposure,
          maxExposure: _maxExposure,
          zoom: 1.0,
          minZoom: state.minZoom,
          maxZoom: state.maxZoom,
          error: null,
        );

        await _configureCameraAfterReady(controller);
        if (!mounted || !_isActiveController(controller)) return;
        state = state.copyWith(isReady: true);
        unawaited(_warmUpAfterCameraReady());
        unawaited(_resumePendingVideoProcessing());
      } else {
        state = state.copyWith(
          isReady: false,
          clearController: true,
          error: "Camera controller not initialized after setup",
        );
      }
    } catch (e) {
      debugPrint('Init error: $e');
      String errorMessage = e.toString();
      if (errorMessage.contains('CameraException')) {
        errorMessage =
            "Camera Error: Please ensure no other app is using the camera.";
      }
      state = state.copyWith(
        isReady: false,
        clearController: true,
        error: errorMessage,
      );
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _configureCameraAfterReady(CameraController controller) async {
    try {
      if (!_isActiveController(controller)) return;

      // CameraX is sensitive to parallel native commands. Keep startup camera
      // configuration strictly sequential to avoid Pigeon/FlutterJNI races.
      await _safeCameraCommand(
        controller,
        'initial flash off',
        () => controller.setFlashMode(FlashMode.off),
      );
      // The repository already establishes automatic focus and exposure while
      // initializing the controller. Repeating those commands (and resetting
      // center points) delayed the first photo on CameraX devices.

      final minExposure = await _safeCameraQuery<double>(
        controller,
        'min exposure',
        controller.getMinExposureOffset,
      );
      final maxExposure = await _safeCameraQuery<double>(
        controller,
        'max exposure',
        controller.getMaxExposureOffset,
      );
      final minZoom = await _safeCameraQuery<double>(
        controller,
        'min zoom',
        controller.getMinZoomLevel,
      );
      final maxZoom = await _safeCameraQuery<double>(
        controller,
        'max zoom',
        controller.getMaxZoomLevel,
      );

      if (!_isActiveController(controller)) return;

      _minExposure = minExposure ?? _minExposure;
      _maxExposure = maxExposure ?? _maxExposure;
      _currentExposure = 0.0.clamp(_minExposure, _maxExposure);

      state = state.copyWith(
        exposure: _currentExposure,
        minExposure: _minExposure,
        maxExposure: _maxExposure,
        minZoom: minZoom ?? state.minZoom,
        maxZoom: maxZoom ?? state.maxZoom,
      );
    } catch (e) {
      debugPrint('Deferred camera setup skipped: $e');
    }
  }

  Future<void> _warmUpAfterCameraReady() async {
    try {
      await Future.delayed(const Duration(milliseconds: 200));
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
      // CameraX Recorder orientation is fixed for the active MP4. Do not
      // mutate or GPU-rotate the camera stream here. The realtime overlay
      // update below carries the new physical orientation and is rendered in
      // the fixed encoder canvas, matching stock-camera recording semantics.
      _recordCurrentVideoOverlaySample();
    }
  }

  OverlayRenderSnapshot _currentOverlaySnapshot() {
    return ref.read(overlayRenderSnapshotProvider);
  }

  OverlayRenderSnapshot _currentRecordingOverlaySnapshot() {
    final current = _currentOverlaySnapshot();
    if (_recordingCaptureOrientation == null) return current;

    // The encoder surface/target rotation stays frozen at recording start,
    // but overlay layout follows the phone's *physical* UI/photo orientation.
    // Do not use the CameraX landscape-label adapter here: that adapter exists
    // only for VideoCapture target rotation and swaps left/right by design.
    // Keeping the raw physical label lets the overlay use the same orientation
    // convention as the already-correct PHOTO/preview renderer.
    return OverlayRenderSnapshot(
      data: current.data,
      settings: current.settings,
      orientation: state.orientation,
    );
  }

  double _recordingViewportAspectRatio() {
    // The MP4 canvas stays fixed, but the logical overlay viewport follows the
    // current physical device orientation. The realtime rasterizer rotates
    // that logical viewport back into the fixed encoder canvas without
    // touching camera pixels.
    return state.aspectRatio.forOrientation(state.orientation);
  }

  void _recordCurrentVideoOverlaySample({bool force = false}) {
    if (!force && !state.isRecording) return;
    final snapshot = _currentRecordingOverlaySnapshot();
    _recordingSession.recordOverlay(
      snapshot,
      force: force,
    );
    if (state.isRecording && state.isRealtimeOverlayActive) {
      ref.read(videoRecordingBackendProvider).updateRealtimeOverlay(
            snapshot,
            viewportAspectRatio: _recordingViewportAspectRatio(),
            isFrontCamera: state.currentLens == CameraLensType.front,
          );
    }
  }

  // ================= LIFECYCLE =================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final appState = state;
    _latestLifecycleState = appState;
    final generation = ++_lifecycleGeneration;
    debugPrint("AppLifecycleState: $appState");

    if (appState == AppLifecycleState.paused ||
        appState == AppLifecycleState.hidden ||
        appState == AppLifecycleState.detached) {
      ref.read(locationTrackingActiveProvider.notifier).state = false;
    } else if (appState == AppLifecycleState.resumed) {
      ref.read(locationTrackingActiveProvider.notifier).state = true;
    }

    _lifecycleQueue = _lifecycleQueue.catchError((Object error) {
      debugPrint('Previous lifecycle camera operation failed: $error');
    }).then((_) async {
      if (!mounted || generation != _lifecycleGeneration) return;
      await _sessionQueue
          .run(() => _handleLifecycleState(appState, generation));
    });
  }

  Future<void> _handleLifecycleState(
    AppLifecycleState appState,
    int generation,
  ) async {
    if (!mounted || generation != _lifecycleGeneration) return;

    if (appState == AppLifecycleState.inactive) {
      final controller = state.controller;
      if (controller != null && _isActiveController(controller)) {
        await _softFlashQuench(controller);
      }
      return;
    }

    if (appState == AppLifecycleState.paused ||
        appState == AppLifecycleState.hidden ||
        appState == AppLifecycleState.detached) {
      final controller = state.controller;
      final wasRecording = state.isRecording;

      // Critical order: remove CameraPreview from widget tree BEFORE disposing
      // the native CameraController. Otherwise Flutter can rebuild one frame
      // late and CameraPreview throws "Disposed CameraController".
      _isDisposing = true;
      state = state.copyWith(
        isReady: false,
        isCapturing: false,
        error: null,
      );
      await Future<void>.delayed(const Duration(milliseconds: 16));

      try {
        if (wasRecording || _nativeRecordingStarted) {
          await _stopVideoRecordingInternal();
          await Future.delayed(const Duration(milliseconds: 200));
        }

        if (controller != null && _isActiveController(controller)) {
          await _softFlashQuench(controller);
        }

        state = state.copyWith(
          clearController: true,
          isReady: false,
          isCapturing: false,
          isRecording: false,
        );
        await Future<void>.delayed(const Duration(milliseconds: 16));
        await ref.read(cameraRepositoryProvider).dispose();
        debugPrint("Camera disposed for backgrounding.");
      } catch (e) {
        debugPrint("Error on backgrounding: $e");
        state = state.copyWith(
          clearController: true,
          isReady: false,
          isCapturing: false,
          isRecording: false,
        );
      } finally {
        _isDisposing = false;
      }
      return;
    }

    if (appState == AppLifecycleState.resumed) {
      // Debounce a quick background/foreground bounce. If another lifecycle
      // event arrives during the delay, this generation becomes stale.
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted ||
          generation != _lifecycleGeneration ||
          _latestLifecycleState != AppLifecycleState.resumed) {
        return;
      }
      if (state.controller != null &&
          state.isReady &&
          state.controller!.value.isInitialized) {
        return;
      }
      await initialize();
    }
  }

  // ================= REFRESH =================

  Future<void> refreshCamera() => _sessionQueue.run(_refreshCameraInternal);

  Future<void> _refreshCameraInternal() async {
    if (!mounted) return;
    debugPrint("Refreshing camera manually...");
    if (state.isRecording || _nativeRecordingStarted) {
      await _stopVideoRecordingInternal();
    }
    // Hide preview first, then dispose. This avoids a stale CameraPreview frame
    // calling buildPreview() on a disposed native controller.
    state = state.copyWith(clearController: true, isReady: false, error: null);
    await Future<void>.delayed(const Duration(milliseconds: 16));
    await ref.read(cameraRepositoryProvider).dispose();
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

      await _safeCameraCommand(
        controller,
        'focus mode auto',
        () => controller.setFocusMode(FocusMode.auto),
      );
      await _safeCameraCommand(
        controller,
        'exposure mode auto',
        () => controller.setExposureMode(ExposureMode.auto),
      );
      await _safeCameraCommand(
        controller,
        'focus point',
        () => controller.setFocusPoint(Offset(dx, dy)),
      );
      await _safeCameraCommand(
        controller,
        'exposure point',
        () => controller.setExposurePoint(Offset(dx, dy)),
      );
    } catch (e) {
      debugPrint("Overall focus point error: $e");
    }
  }

  Future<void> resetFocus() async {
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      state = state.copyWith(isManualFocus: false);

      await _safeCameraCommand(
        controller,
        'reset focus mode',
        () => controller.setFocusMode(FocusMode.auto),
      );
      await _safeCameraCommand(
        controller,
        'reset exposure mode',
        () => controller.setExposureMode(ExposureMode.auto),
      );
      await _safeCameraCommand(
        controller,
        'reset focus point',
        () => controller.setFocusPoint(null),
      );
      await _safeCameraCommand(
        controller,
        'reset exposure point',
        () => controller.setExposurePoint(null),
      );
    } catch (e) {
      debugPrint("Reset focus error: $e");
    }
  }

  // ================= EXPOSURE =================

  void changeExposure(double delta) {
    final controller = state.controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        state.isCapturing) {
      return;
    }

    final target =
        (_currentExposure + delta).clamp(_minExposure, _maxExposure).toDouble();
    if ((target - _currentExposure).abs() < 0.0005) return;

    _prepareExposureController(controller);
    _currentExposure = target;

    // Keep the HUD attached to the finger instead of waiting for CameraX.
    state = state.copyWith(exposure: target);

    // Do not append every drag event to the repository queue. While one native
    // request is running, this replaces the pending request with the newest
    // target, so shutter capture can never sit behind a full gesture history.
    _exposureUpdates.submit(
      target,
      (value) => _applyExposureTarget(controller, value),
    );
  }

  void _prepareExposureController(CameraController controller) {
    if (identical(_exposureController, controller)) return;

    _exposureUpdates.cancelPending();
    _exposureController = controller;
    _lastSubmittedExposure = state.exposure;
  }

  Future<void> _applyExposureTarget(
    CameraController controller,
    double target,
  ) async {
    if (!_isActiveController(controller)) return;
    if (identical(_exposureController, controller) &&
        _lastSubmittedExposure != null &&
        (target - _lastSubmittedExposure!).abs() < 0.0005) {
      return;
    }

    try {
      await ref.read(cameraRepositoryProvider).runExclusive(() async {
        if (!_isActiveController(controller)) return;
        await controller.setExposureOffset(target);
      });
      if (_isActiveController(controller) &&
          identical(_exposureController, controller)) {
        _lastSubmittedExposure = target;
      }
    } catch (e) {
      if (_isActiveController(controller)) {
        debugPrint('Exposure update skipped: $e');
      }
    }
  }

  Future<void> _settleExposureForCapture(
    CameraController controller,
  ) async {
    _prepareExposureController(controller);
    final target =
        _currentExposure.clamp(_minExposure, _maxExposure).toDouble();
    await _exposureUpdates.flush(
      target,
      (value) => _applyExposureTarget(controller, value),
    );
  }

  void _resetExposurePipeline() {
    _exposureUpdates.cancelPending();
    _exposureController = null;
    _lastSubmittedExposure = null;
  }

  // ================= ZOOM =================

  /// One-off zoom change used by non-gesture UI. Pinch zoom uses a separate
  /// frame-synchronised driver below so it is never blocked behind unrelated
  /// camera operations or by completion of an older CameraX zoom request.
  Future<void> setZoom(double zoom) async {
    _zoomAnimationGeneration++;
    _cancelScheduledZoomFrame();
    _zoomDriveGeneration++;
    _zoomGestureActive = false;
    await _commitFinalZoom(zoom);
  }

  /// Starts direct-manipulation zoom. CameraX explicitly supports a newer
  /// zoom-ratio request superseding an older one, so gesture traffic must not
  /// be serialised through the repository-wide camera-operation queue.
  /// Instead we submit at most the newest target once per Flutter frame.
  void beginZoomGesture() {
    _zoomAnimationGeneration++;
    _cancelScheduledZoomFrame();
    _zoomDriveGeneration++;
    _zoomGestureActive = true;
    _pendingZoom = null;
    _prepareZoomController();
  }

  void updateZoomGesture(double zoom) {
    if (!_zoomGestureActive) {
      beginZoomGesture();
    }

    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;
    _prepareZoomController();
    _pendingZoom = zoom.clamp(state.minZoom, state.maxZoom).toDouble();
    _scheduleZoomFrame(controller, _zoomDriveGeneration);
  }

  Future<void> endZoomGesture(double zoom) async {
    _zoomGestureActive = false;
    _cancelScheduledZoomFrame();
    _pendingZoom = null;
    _zoomDriveGeneration++;
    await _commitFinalZoom(zoom);
  }

  Future<void> animateZoomTo(
    double zoom, {
    Duration duration = const Duration(milliseconds: 220),
  }) async {
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;

    _zoomGestureActive = false;
    _cancelScheduledZoomFrame();
    _prepareZoomController();
    final driveGeneration = ++_zoomDriveGeneration;
    final generation = ++_zoomAnimationGeneration;

    final startZoom = (_lastSubmittedZoom ?? state.zoom)
        .clamp(state.minZoom, state.maxZoom)
        .toDouble();
    final targetZoom = zoom.clamp(state.minZoom, state.maxZoom).toDouble();
    if (duration <= Duration.zero || (targetZoom - startZoom).abs() < 0.005) {
      await _commitFinalZoom(targetZoom);
      return;
    }

    // Drive programmatic zoom on display-frame cadence. Do not await each
    // intermediate CameraX request: CameraX treats a newer zoom ratio as the
    // authoritative value and cancels the obsolete future by design.
    final stopwatch = Stopwatch()..start();
    while (mounted &&
        generation == _zoomAnimationGeneration &&
        driveGeneration == _zoomDriveGeneration) {
      final progress = (stopwatch.elapsedMicroseconds / duration.inMicroseconds)
          .clamp(0.0, 1.0)
          .toDouble();
      final eased = Curves.easeOutCubic.transform(progress);
      final value = startZoom + ((targetZoom - startZoom) * eased);
      _submitGestureZoom(controller, value, driveGeneration);
      if (progress >= 1) break;
      await SchedulerBinding.instance.endOfFrame;
    }
    stopwatch.stop();

    if (!mounted ||
        generation != _zoomAnimationGeneration ||
        driveGeneration != _zoomDriveGeneration) {
      return;
    }
    await _commitFinalZoom(targetZoom);
  }

  void _prepareZoomController() {
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (identical(_zoomController, controller)) return;

    _zoomController = controller;
    _lastSubmittedZoom = state.zoom;
    _pendingZoom = null;
    _cancelScheduledZoomFrame();
    _zoomDriveGeneration++;
  }

  void _scheduleZoomFrame(CameraController controller, int generation) {
    if (_zoomFrameCallbackId != null) return;

    _zoomFrameCallbackId = SchedulerBinding.instance.scheduleFrameCallback((_) {
      _zoomFrameCallbackId = null;
      if (!mounted ||
          !_zoomGestureActive ||
          generation != _zoomDriveGeneration ||
          !_isActiveController(controller)) {
        return;
      }

      final target = _pendingZoom;
      _pendingZoom = null;
      if (target != null) {
        _submitGestureZoom(controller, target, generation);
      }

      // An input event may have landed while this callback was running. Keep
      // only that newest value for the next display frame.
      if (_pendingZoom != null &&
          _zoomGestureActive &&
          generation == _zoomDriveGeneration) {
        _scheduleZoomFrame(controller, generation);
      }
    });
  }

  void _submitGestureZoom(
    CameraController controller,
    double zoom,
    int generation,
  ) {
    if (!mounted ||
        generation != _zoomDriveGeneration ||
        !_isActiveController(controller)) {
      return;
    }

    final target = zoom.clamp(state.minZoom, state.maxZoom).toDouble();
    final previous = _lastSubmittedZoom;
    if (previous != null && (target - previous).abs() < 0.0005) return;

    // Publish the requested target before the asynchronous CameraX result.
    // During a pinch the HUD owns visual feedback; CameraState publication is
    // intentionally deferred until gesture end to avoid rebuilding preview.
    _lastSubmittedZoom = target;
    unawaited(_applySupersedingZoom(controller, target, generation));
  }

  Future<void> _applySupersedingZoom(
    CameraController controller,
    double target,
    int generation,
  ) async {
    try {
      await controller.setZoomLevel(target);
    } catch (error) {
      // A newer CameraX zoom request can cancel the older future. The pinned
      // camera_android_camerax plugin normalises that cancellation to success;
      // lifecycle/unsupported failures still arrive here and are non-fatal.
      if (mounted &&
          generation == _zoomDriveGeneration &&
          _isActiveController(controller)) {
        debugPrint('Zoom update skipped: $error');
      }
    }
  }

  Future<void> _commitFinalZoom(double zoom) async {
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;
    _prepareZoomController();

    final generation = _zoomDriveGeneration;
    final target = zoom.clamp(state.minZoom, state.maxZoom).toDouble();
    _lastSubmittedZoom = target;
    try {
      await controller.setZoomLevel(target);
    } catch (error) {
      if (mounted &&
          generation == _zoomDriveGeneration &&
          _isActiveController(controller)) {
        debugPrint('Final zoom commit failed: $error');
      }
      return;
    }

    if (!mounted ||
        generation != _zoomDriveGeneration ||
        !_isActiveController(controller)) {
      return;
    }
    if ((state.zoom - target).abs() >= 0.001) {
      state = state.copyWith(zoom: target);
    }
  }

  void _cancelScheduledZoomFrame() {
    final callbackId = _zoomFrameCallbackId;
    _zoomFrameCallbackId = null;
    if (callbackId != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(callbackId);
    }
  }

  /// Soft flash quench only. Avoid aggressive torch toggling after capture
  /// because some CameraX devices crash when flash commands race teardown.
  Future<void> _softFlashQuench(CameraController controller) async {
    await _safeCameraCommand(
      controller,
      'flash off',
      () => controller.setFlashMode(FlashMode.off),
    );
    await Future.delayed(const Duration(milliseconds: 40));
  }

  // ================= FLASH =================

  Future<void> setFlashMode(FlashMode mode) async {
    state = state.copyWith(flashMode: mode);

    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      if (mode == FlashMode.off) {
        await _safeCameraCommand(
          controller,
          'set flash off',
          () => controller.setFlashMode(FlashMode.off),
        );
      } else {
        if (state.isRecording && state.currentLens != CameraLensType.front) {
          await _safeCameraCommand(
            controller,
            'set recording torch',
            () => controller.setFlashMode(FlashMode.torch),
          );
        } else {
          // For photos, keep hardware flash OFF and enable torch only during capture.
          await _safeCameraCommand(
            controller,
            'keep photo flash off',
            () => controller.setFlashMode(FlashMode.off),
          );
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
    if (state.isRecording) {
      _recordCurrentVideoOverlaySample(force: true);
    }
  }

  // ================= CAMERA SWITCH =================

  Future<void> switchCamera() => _sessionQueue.run(_switchCameraInternal);

  Future<void> _switchCameraInternal() async {
    if (_isInitializing ||
        _isDisposing ||
        !mounted ||
        _latestLifecycleState != AppLifecycleState.resumed ||
        _isRestarting ||
        _startRecordingInFlight ||
        _stopRecordingInFlight) {
      return;
    }

    _isRestarting = true;
    try {
      final wasRecording = state.isRecording;
      final previousLens = state.currentLens;
      final nextLens = previousLens == CameraLensType.front
          ? CameraLensType.normal
          : CameraLensType.front;

      if (wasRecording) {
        final mirrorRequested =
            ref.read(cameraSettingsProvider).mirrorFrontVideo;
        final canKeepOneNativeFile =
            !mirrorRequested || _currentRecordingUsesNativeFrontMirror;

        if (canKeepOneNativeFile) {
          final backend = ref.read(videoRecordingBackendProvider);
          final switched = await backend.switchLensWhileRecording(nextLens);
          if (switched) {
            _recordingSession.markCurrentSegmentCameraSwitch();
            state = state.copyWith(
              currentLens: nextLens,
              controller: state.controller,
              isReady: true,
              error: null,
            );
            await _refreshCapabilitiesAfterLensSwitch(state.controller);
            await _restoreRecordingFlashForLens(nextLens);
            _recordCurrentVideoOverlaySample(force: true);
            debugPrint(
              'Persistent CameraX lens switch kept the active recording file.',
            );
            return;
          }
        } else {
          debugPrint(
            'Persistent lens switch skipped because front mirror still needs '
            'per-segment post-processing.',
          );
        }

        await _switchCameraWithSegmentBoundary(
          previousLens: previousLens,
          nextLens: nextLens,
        );
        return;
      }

      final controller = await _initializeFreshLens(nextLens);
      await _refreshCapabilitiesAfterLensSwitch(controller);
    } catch (e) {
      debugPrint('Switch camera error: $e');
      if (mounted && _recordingSession.isActive) {
        // A failed next-lens initialization must not discard the segment that
        // was already finalized successfully before the switch.
        await _stopVideoRecordingInternal();
      } else if (mounted && state.isRecording) {
        _recordingSession.abort();
        ++_realtimeActivationToken;
        _nativeRecordingStarted = false;
        await ref.read(videoRecordingBackendProvider).finishRealtimeOverlay();
        _currentRecordingUsesNativeFrontMirror = false;
        _recordingCaptureOrientation = null;
      }
      if (mounted) {
        state = state.copyWith(
          isReady: false,
          error: e.toString(),
          isRecording: false,
          isRealtimeOverlayActive: false,
        );
      }
    } finally {
      _isRestarting = false;
    }
  }

  Future<void> _switchCameraWithSegmentBoundary({
    required CameraLensType previousLens,
    required CameraLensType nextLens,
  }) async {
    final backend = ref.read(videoRecordingBackendProvider);
    ++_realtimeActivationToken;
    _recordCurrentVideoOverlaySample(force: true);
    await backend.freezeRealtimeOverlayUpdatesForStop();
    final segmentRealtime = await backend.inspectRealtimeOverlaySegment();
    final segmentPath = await backend.stop();
    _nativeRecordingStarted = false;
    _recordingSession.addSegment(
      VideoRecordingSegment(
        path: segmentPath,
        lens: previousLens,
        mirror: _requiresMirrorPostProcess(previousLens),
        realtimeOverlayApplied: segmentRealtime.applied,
        realtimeOverlayHealthy: segmentRealtime.healthy,
        containsCameraSwitches:
            _recordingSession.takeCurrentSegmentCameraSwitchMarker(),
      ),
    );

    // Stop/background may arrive while Finalize is pending. Keep the finished
    // segment and save it through the stop path, without opening a new recorder
    // against a stopped Activity lifecycle.
    if (!await _canContinueRecordingSwitch()) return;

    final controller = await _initializeFreshLens(nextLens);
    await _refreshCapabilitiesAfterLensSwitch(controller);

    if (!await _canContinueRecordingSwitch()) return;

    final mirrorRequested = ref.read(cameraSettingsProvider).mirrorFrontVideo;
    _currentRecordingUsesNativeFrontMirror =
        await backend.configureFrontVideoMirroring(mirrorRequested);

    final shouldAttemptRealtime =
        state.isRealtimeOverlayActive || backend.isRealtimeOverlayActive;
    var realtimePrepared = false;
    if (shouldAttemptRealtime) {
      final recordingSnapshot = _currentRecordingOverlaySnapshot();
      realtimePrepared = await backend.prepareRealtimeOverlay(
        recordingSnapshot,
        viewportAspectRatio: _recordingViewportAspectRatio(),
        captureOrientation: _recordingCaptureOrientation,
        isFrontCamera: nextLens == CameraLensType.front,
      );
    }

    await _restoreRecordingFlashForLens(nextLens);
    if (!await _canContinueRecordingSwitch()) return;
    await backend.start();
    _nativeRecordingStarted = true;
    if (!await _canContinueRecordingSwitch()) return;
    state = state.copyWith(
      isRecording: true,
      isRealtimeOverlayActive: false,
    );
    final activationToken = ++_realtimeActivationToken;
    if (realtimePrepared) {
      unawaited(_completeRealtimeOverlayActivation(
        backend: backend,
        activationToken: activationToken,
      ));
    }
    _recordCurrentVideoOverlaySample(force: true);
  }

  Future<bool> _canContinueRecordingSwitch() async {
    if (!mounted) return false;
    if (_latestLifecycleState == AppLifecycleState.resumed &&
        _pendingStopRequests == 0) {
      return true;
    }
    // Finish inside the current transition. A fast pause/resume can invalidate
    // the queued pause handler, so merely returning would strand the session.
    await _stopVideoRecordingInternal();
    return false;
  }

  Future<CameraController> _initializeFreshLens(
    CameraLensType lens, {
    bool forceRecreate = false,
  }) async {
    state = state.copyWith(
      currentLens: lens,
      isReady: false,
      clearController: true,
      error: null,
    );

    final repo = ref.read(cameraRepositoryProvider);
    if (forceRecreate) {
      await repo.dispose();
    }
    await repo.initialize(lens);
    final controller = repo.controller;
    if (controller == null || !controller.value.isInitialized) {
      throw Exception('Camera $lens failed to initialize during lens switch.');
    }

    // Publish the controller before capability queries. _safeCameraQuery only
    // accepts the controller that is currently owned by state.
    state = state.copyWith(
      controller: controller,
      isReady: false,
      exposure: 0.0,
      zoom: 1.0,
      error: null,
    );
    return controller;
  }

  Future<void> _refreshCapabilitiesAfterLensSwitch(
    CameraController? controller,
  ) async {
    if (controller == null || !controller.value.isInitialized) return;

    final minExposure = await _safeCameraQuery<double>(
      controller,
      'switch min exposure',
      controller.getMinExposureOffset,
    );
    final maxExposure = await _safeCameraQuery<double>(
      controller,
      'switch max exposure',
      controller.getMaxExposureOffset,
    );
    final minZoom = await _safeCameraQuery<double>(
      controller,
      'switch min zoom',
      controller.getMinZoomLevel,
    );
    final maxZoom = await _safeCameraQuery<double>(
      controller,
      'switch max zoom',
      controller.getMaxZoomLevel,
    );

    _minExposure = minExposure ?? _minExposure;
    _maxExposure = maxExposure ?? _maxExposure;
    _currentExposure = 0.0.clamp(_minExposure, _maxExposure);

    if (!mounted || !_isActiveController(controller)) return;
    state = state.copyWith(
      isReady: true,
      controller: controller,
      exposure: _currentExposure,
      minExposure: _minExposure,
      maxExposure: _maxExposure,
      zoom: 1.0,
      minZoom: minZoom ?? state.minZoom,
      maxZoom: maxZoom ?? state.maxZoom,
      error: null,
    );
  }

  Future<void> _restoreRecordingFlashForLens(CameraLensType lens) async {
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (lens == CameraLensType.front) {
      await _safeCameraCommand(
        controller,
        'front lens torch off',
        () => controller.setFlashMode(FlashMode.off),
      );
      return;
    }

    if (state.flashMode == FlashMode.always) {
      await _safeCameraCommand(
        controller,
        'switch recording torch',
        () => controller.setFlashMode(FlashMode.torch),
      );
    }
  }

  // ================= CAPTURE =================

  void setCameraMode(CameraMode mode) {
    state = state.copyWith(cameraMode: mode);
    if (mode == CameraMode.video) {
      // Prewarm without forcing a controller recreation. The record action
      // performs the authoritative builder-time mirror check serially.
      unawaited(
        _prepareVideoForCurrentController(allowMirrorRebuild: false),
      );
    }
  }

  Future<bool> _prepareVideoForCurrentController({
    bool allowMirrorRebuild = true,
  }) async {
    var controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return false;

    final backend = ref.read(videoRecordingBackendProvider);
    await backend.armRealtimeOverlay();

    final mirrorRequested = ref.read(cameraSettingsProvider).mirrorFrontVideo;
    var nativeMirrorReady =
        await backend.configureFrontVideoMirroring(mirrorRequested);

    // CameraX mirror mode is a VideoCapture.Builder setting. If this controller
    // was created with a different mode, rebuild the same lens once while the
    // recorder is idle. The native bridge stores the requested mode, so the
    // patched VideoCaptureProxyApi applies it during the new build().
    if (allowMirrorRebuild &&
        !nativeMirrorReady &&
        !controller.value.isRecordingVideo &&
        await backend.requiresFrontVideoMirrorRebuild(mirrorRequested)) {
      controller = await _initializeFreshLens(
        state.currentLens,
        forceRecreate: true,
      );
      await _refreshCapabilitiesAfterLensSwitch(controller);
      nativeMirrorReady =
          await backend.configureFrontVideoMirroring(mirrorRequested);
    }

    controller = state.controller;
    if (controller == null || !controller.value.isInitialized) {
      return nativeMirrorReady;
    }
    await _safeCameraCommand(
      controller,
      'video pre-warm',
      controller.prepareForVideoRecording,
    );
    return nativeMirrorReady;
  }

  bool _requiresMirrorPostProcess(CameraLensType lens) {
    final mirrorRequested = ref.read(cameraSettingsProvider).mirrorFrontVideo;
    return lens == CameraLensType.front &&
        mirrorRequested &&
        !_currentRecordingUsesNativeFrontMirror;
  }

  Future<void> setFrontVideoMirroring(bool mirror) async {
    final settingsNotifier = ref.read(cameraSettingsProvider.notifier);
    final backend = ref.read(videoRecordingBackendProvider);

    if (!state.isRecording || state.currentLens != CameraLensType.front) {
      await settingsNotifier.setMirrorFrontVideo(mirror);
      // Apply immediately to the already-created VideoCapture when possible so
      // the next recording starts with the correct capture-time transform.
      await backend.configureFrontVideoMirroring(mirror);
      return;
    }

    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) {
      await settingsNotifier.setMirrorFrontVideo(mirror);
      return;
    }

    var segmentClosed = false;
    try {
      ++_realtimeActivationToken;
      _recordCurrentVideoOverlaySample(force: true);
      await backend.freezeRealtimeOverlayUpdatesForStop();
      final segmentRealtime = await backend.inspectRealtimeOverlaySegment();
      final segmentPath = await backend.stop();
      _nativeRecordingStarted = false;
      segmentClosed = true;
      _recordingSession.addSegment(
        VideoRecordingSegment(
          path: segmentPath,
          lens: state.currentLens,
          mirror: _requiresMirrorPostProcess(state.currentLens),
          realtimeOverlayApplied: segmentRealtime.applied,
          realtimeOverlayHealthy: segmentRealtime.healthy,
          containsCameraSwitches:
              _recordingSession.takeCurrentSegmentCameraSwitchMarker(),
        ),
      );

      await settingsNotifier.setMirrorFrontVideo(mirror);
      // The just-finished recorder is idle, so a builder-time mirror mismatch
      // can safely recreate this front-camera VideoCapture before the next
      // segment starts. Unsupported devices simply return false and keep hflip
      // post-processing for the new segment.
      _currentRecordingUsesNativeFrontMirror =
          await _prepareVideoForCurrentController();

      final shouldAttemptRealtime =
          state.isRealtimeOverlayActive || backend.isRealtimeOverlayActive;
      var realtimePrepared = false;
      if (shouldAttemptRealtime) {
        final recordingSnapshot = _currentRecordingOverlaySnapshot();
        realtimePrepared = await backend.prepareRealtimeOverlay(
          recordingSnapshot,
          viewportAspectRatio: _recordingViewportAspectRatio(),
          captureOrientation: _recordingCaptureOrientation,
          isFrontCamera: state.currentLens == CameraLensType.front,
        );
      }

      await backend.start();
      _nativeRecordingStarted = true;
      state = state.copyWith(
        isRecording: true,
        isRealtimeOverlayActive: false,
      );
      final activationToken = ++_realtimeActivationToken;
      if (realtimePrepared) {
        unawaited(_completeRealtimeOverlayActivation(
          backend: backend,
          activationToken: activationToken,
        ));
      }
      _recordCurrentVideoOverlaySample(force: true);
    } catch (e) {
      debugPrint('Mirror toggle while recording failed: $e');
      await settingsNotifier.setMirrorFrontVideo(mirror);
      if (segmentClosed) {
        _recordingSession.abort();
        ++_realtimeActivationToken;
        _nativeRecordingStarted = false;
        await backend.finishRealtimeOverlay();
        _currentRecordingUsesNativeFrontMirror = false;
        _recordingCaptureOrientation = null;
        state = state.copyWith(
          isRecording: false,
          isRealtimeOverlayActive: false,
        );
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

    final deviceOrientation = ref.read(deviceOrientationProvider);
    final captureMirror = state.currentLens == CameraLensType.front &&
        ref.read(cameraSettingsProvider).mirrorFrontPhoto;
    state = state.copyWith(
      isCapturing: true,
      captureOrientation: deviceOrientation,
      captureLens: state.currentLens,
      captureMirror: captureMirror,
    );

    try {
      if (!_isActiveController(controller)) return null;

      final overlayData = ref.read(overlayPreviewProvider);
      ref.read(capturedOverlayProvider.notifier).state = overlayData;

      final repo = ref.read(cameraRepositoryProvider);

      if (state.flashMode == FlashMode.always) {
        if (state.currentLens == CameraLensType.front) {
          await Future.delayed(const Duration(milliseconds: 20));
        } else {
          await _safeCameraCommand(
            controller,
            'capture torch on',
            () => controller.setFlashMode(FlashMode.torch),
          );
          await Future.delayed(_flashExposureSettleDelay);
        }
      }

      // Collapse any remaining gesture update to one final exposure command,
      // then capture under the existing end-to-end timeout.
      final path = await (() async {
        await _settleExposureForCapture(controller);
        return repo.takePicture();
      })()
          .timeout(_photoCaptureTimeout);

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
      // Restore under the camera queue. Do not leave flash/preview cleanup running
      // unawaited after a capture because it can race a fast back/resume/dispose.
      _captureInFlight = false;
      await _restoreCameraState(controller);
      state = state.copyWith(isCapturing: false);
    }
  }

  Future<bool> capturePhotoDuringRecording() async {
    // A video with rewarded premium settings owns those one-use rewards until
    // it stops; a simultaneous still must not spend the same ads twice.
    if (_recordingUsesRewardedFeatures) return false;
    final controller = state.controller;

    if (!state.isRecording ||
        !state.isReady ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        state.isCapturing ||
        _captureInFlight ||
        _stopRecordingInFlight) {
      return false;
    }

    _captureInFlight = true;
    unawaited(HapticFeedback.mediumImpact());

    final overlayData = ref.read(overlayPreviewProvider);
    ref.read(capturedOverlayProvider.notifier).state = overlayData;
    final overlaySettings = ref.read(effectiveOverlaySettingsProvider);
    final projectId = ref.read(effectiveActiveProjectIdProvider);
    final deviceOrientation = ref.read(deviceOrientationProvider);
    final captureLens = state.currentLens;
    final captureMirror = captureLens == CameraLensType.front &&
        ref.read(cameraSettingsProvider).mirrorFrontPhoto;
    final aspectRatio = state.aspectRatio;

    state = state.copyWith(
      isCapturing: true,
      captureOrientation: deviceOrientation,
      captureLens: captureLens,
      captureMirror: captureMirror,
    );

    try {
      final repo = ref.read(cameraRepositoryProvider);
      final path = await (() async {
        await _settleExposureForCapture(controller);
        return repo.takePicture();
      })()
          .timeout(_photoCaptureTimeout);
      final originalFile = File(path);
      final rewardAccess = ref.read(rewardedCaptureAccessProvider);
      rewardAccess.reserveBackgroundImage(path);
      final enqueued =
          await ref.read(overlayViewModelProvider.notifier).saveCapturedImage(
                original: originalFile,
                orientation: deviceOrientation,
                overlayData: overlayData,
                showOverlay: true,
                showWatermark: true,
                aspectRatio: aspectRatio,
                mirror: captureMirror,
                settingsOverride: overlaySettings,
                projectId: projectId,
              );
      if (!enqueued) {
        rewardAccess.failBackgroundImage(path);
        return false;
      }

      unawaited(HapticFeedback.lightImpact());
      return true;
    } on TimeoutException catch (e) {
      debugPrint('Recording photo capture timeout: $e');
      return false;
    } catch (e) {
      debugPrint('Recording photo capture error: $e');
      if (e.toString().contains('CameraException')) {
        debugPrint(
            "Recording photo capture hit a camera exception. Video recording was left untouched.");
      }
      return false;
    } finally {
      _captureInFlight = false;
      state = state.copyWith(isCapturing: false);
    }
  }

  Future<void> _restoreCameraState(CameraController? controller) async {
    try {
      if (controller == null || !_isActiveController(controller)) return;

      if (state.flashMode == FlashMode.always &&
          state.currentLens != CameraLensType.front) {
        await _safeCameraCommand(
          controller,
          'restore flash off',
          () => controller.setFlashMode(FlashMode.off),
        );
      }

      if (_isActiveController(controller) && controller.value.isPreviewPaused) {
        await _safeCameraCommand(
          controller,
          'resume preview',
          controller.resumePreview,
        );
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

  Future<bool> startVideoRecording({bool clearSegments = true}) =>
      _sessionQueue.run(
        () => _startVideoRecordingInternal(clearSegments: clearSegments),
      );

  Future<bool> _startVideoRecordingInternal(
      {required bool clearSegments}) async {
    if (!mounted ||
        _isDisposing ||
        _isRestarting ||
        _latestLifecycleState != AppLifecycleState.resumed) {
      return false;
    }
    final initialController = state.controller;
    if (initialController == null ||
        !initialController.value.isInitialized ||
        state.isRecording ||
        _startRecordingInFlight ||
        _stopRecordingInFlight ||
        (state.processingProgress != null)) {
      return false;
    }

    _startRecordingInFlight = true;
    _recordingUsesRewardedFeatures = false;
    try {
      state = state.copyWith(
        processingMessage: null,
        videoProcessingError: null,
      );

      final storage = await RecordingStorageGuard.check();
      if (!storage.canStart) {
        final freeMiB = (storage.usableBytes! / (1024 * 1024)).floor();
        state = state.copyWith(
          processingMessage: null,
          videoProcessingError:
              'Not enough free storage to start video recording ($freeMiB MiB available).',
        );
        return false;
      }

      await ref.read(projectProvider.notifier).ready;
      await ref.read(overlaySettingsProvider.notifier).ready;

      // This may recreate the current Android CameraX controller once when the
      // existing VideoCapture was built with a different mirror policy. It
      // happens before recording, so the saved file needs no later hflip.
      _currentRecordingUsesNativeFrontMirror =
          await _prepareVideoForCurrentController();

      final controller = state.controller;
      if (controller == null ||
          !controller.value.isInitialized ||
          _latestLifecycleState != AppLifecycleState.resumed) {
        return false;
      }

      if (state.flashMode == FlashMode.always &&
          state.currentLens != CameraLensType.front) {
        await _safeCameraCommand(
          controller,
          'start recording torch',
          () => controller.setFlashMode(FlashMode.torch),
        );
      }

      final backend = ref.read(videoRecordingBackendProvider);
      final initialSnapshot = _currentOverlaySnapshot();
      final recordingStartPhysicalOrientation =
          ref.read(deviceOrientationProvider);
      _recordingCaptureOrientation = toVideoCaptureOrientation(
        recordingStartPhysicalOrientation,
      );
      final initialRecordingSnapshot = OverlayRenderSnapshot(
        data: initialSnapshot.data,
        settings: initialSnapshot.settings,
        orientation: recordingStartPhysicalOrientation,
      );
      debugPrint(
        'Video recording orientation locked: '
        'physical=${recordingStartPhysicalOrientation.name} '
        'capture=${_recordingCaptureOrientation!.name}',
      );
      final realtimeOverlayPrepared = await backend.prepareRealtimeOverlay(
        initialRecordingSnapshot,
        viewportAspectRatio: _recordingViewportAspectRatio(),
        captureOrientation: _recordingCaptureOrientation,
        isFrontCamera: state.currentLens == CameraLensType.front,
      );

      if (!mounted || _latestLifecycleState != AppLifecycleState.resumed) {
        await backend.finishRealtimeOverlay();
        return false;
      }

      // Phase 7.1 prepareRealtimeOverlay() pre-binds VideoCapture and enables
      // the first geometry-correct raster before Recorder.start(). Starting the
      // recorder now cannot leak a clean opening frame on the realtime path.
      await backend.start();
      _nativeRecordingStarted = true;

      // The app can be backgrounded while CameraX is asynchronously creating
      // the recorder. Do not publish a recording state for a controller that
      // the lifecycle handler has already hidden or queued for disposal.
      if (!mounted ||
          _isDisposing ||
          _latestLifecycleState != AppLifecycleState.resumed ||
          !_isActiveController(controller)) {
        debugPrint('Recording start completed after camera became inactive');
        try {
          await backend.freezeRealtimeOverlayUpdatesForStop();
          await backend.stop();
        } catch (_) {}
        _nativeRecordingStarted = false;
        await backend.finishRealtimeOverlay();
        _currentRecordingUsesNativeFrontMirror = false;
        _recordingCaptureOrientation = null;
        if (mounted) {
          state = state.copyWith(
            isRecording: false,
            isRealtimeOverlayActive: false,
          );
        }
        return false;
      }

      _recordingSession.begin(
        initialSnapshot: initialRecordingSnapshot,
        projectId: ref.read(effectiveActiveProjectIdProvider),
        clearSegments: clearSegments,
      );
      _recordingUsesRewardedFeatures =
          ref.read(rewardedCaptureAccessProvider).hasAvailablePhotoRewards;

      // IMPORTANT: publish the native recorder state immediately. Realtime
      // overlay verification is a certification step, not a prerequisite for
      // the Stop button. Keeping isRecording=false while activate() polls the
      // native effect makes a second shutter tap enter Start again instead of
      // Stop even though CameraX is already recording.
      state = state.copyWith(
        isRecording: true,
        isRealtimeOverlayActive: false,
        processingMessage: null,
        videoProcessingError: null,
      );
      _recordingSession.startSampling(
        snapshotReader: _currentRecordingOverlaySnapshot,
        shouldContinue: () => mounted && state.isRecording,
      );

      final activationToken = ++_realtimeActivationToken;
      if (realtimeOverlayPrepared) {
        unawaited(_completeRealtimeOverlayActivation(
          backend: backend,
          activationToken: activationToken,
        ));
      }

      debugPrint('Video recording UI state: RECORDING');
      unawaited(HapticFeedback.heavyImpact());
      return true;
    } catch (e) {
      _recordingUsesRewardedFeatures = false;
      _recordingSession.abort();
      final backend = ref.read(videoRecordingBackendProvider);
      if (_nativeRecordingStarted) {
        try {
          await backend.freezeRealtimeOverlayUpdatesForStop();
          await backend.stop();
        } catch (_) {}
        _nativeRecordingStarted = false;
      }
      ++_realtimeActivationToken;
      await backend.finishRealtimeOverlay();
      _currentRecordingUsesNativeFrontMirror = false;
      _recordingCaptureOrientation = null;
      if (mounted) {
        state = state.copyWith(
          isRecording: false,
          isRealtimeOverlayActive: false,
        );
      }
      debugPrint("Start recording error: $e");
      return false;
    } finally {
      _startRecordingInFlight = false;
    }
  }

  Future<void> _completeRealtimeOverlayActivation({
    required VideoRecordingBackend backend,
    required int activationToken,
  }) async {
    final active = await backend.activateRealtimeOverlay();
    if (!mounted ||
        activationToken != _realtimeActivationToken ||
        !_nativeRecordingStarted ||
        !state.isRecording) {
      return;
    }

    state = state.copyWith(isRealtimeOverlayActive: active);
    if (active) {
      // Push the freshest snapshot once activation is certified. Any overlay
      // changes that happened during the short activation window are therefore
      // not lost.
      _recordCurrentVideoOverlaySample(force: true);
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
    _pendingStopRequests++;
    try {
      await _sessionQueue.run(
        () => _stopVideoRecordingInternal(context: context),
      );
    } finally {
      _pendingStopRequests--;
    }
  }

  Future<void> _stopVideoRecordingInternal({BuildContext? context}) async {
    if (!mounted) return;
    final controller = state.controller;
    if ((!state.isRecording && !_nativeRecordingStarted) ||
        _stopRecordingInFlight) {
      return;
    }

    // Claim and publish Stop synchronously before any overlay verification or
    // CameraX finalization awaits. This gives the shutter tap immediate UI
    // feedback and prevents high-frequency overlay work from making Stop look
    // ignored.
    _stopRecordingInFlight = true;
    ++_realtimeActivationToken;
    _recordingSession.stopSampling();
    state = state.copyWith(
      isRecording: false,
      isRealtimeOverlayActive: false,
      processingMessage: 'Stopping video...',
      videoProcessingError: null,
    );
    debugPrint('Video recording UI state: STOP_REQUESTED');
    unawaited(HapticFeedback.mediumImpact());

    var jobQueuedForProcessing = false;
    String? reservedRewardKey;
    try {
      final backend = ref.read(videoRecordingBackendProvider);

      // Freeze new raster/orientation commits before stopping. This keeps an
      // in-flight Flutter PNG encode from creating a never-rendered native
      // generation after the final camera frame. Native render status itself is
      // retained for certification after Recorder finalization.
      await backend.freezeRealtimeOverlayUpdatesForStop();

      // Stop the actual recorder first. Native overlay status is retained by
      // the bridge until finishRealtimeOverlay(), so certification can happen
      // after the MP4 has stopped without extending the physical recording.
      VideoRecordingSegment? finalSegment;
      if (_nativeRecordingStarted) {
        final path = await backend.stop();
        _nativeRecordingStarted = false;
        final report = await backend.inspectRealtimeOverlaySegment();
        finalSegment = VideoRecordingSegment(
          path: path,
          lens: state.currentLens,
          mirror: _requiresMirrorPostProcess(state.currentLens),
          realtimeOverlayApplied: report.applied,
          realtimeOverlayHealthy: report.healthy,
          containsCameraSwitches:
              _recordingSession.takeCurrentSegmentCameraSwitchMarker(),
        );
      }
      final finalRecordingSnapshot = _currentRecordingOverlaySnapshot();
      final completedSession = _recordingSession.complete(
        finalSegment: finalSegment,
        finalSnapshot: finalRecordingSnapshot,
      );
      final lastSegmentPath = completedSession.segments.last.path;
      _recordingUsesRewardedFeatures = false;
      await backend.finishRealtimeOverlay();
      _currentRecordingUsesNativeFrontMirror = false;
      _recordingCaptureOrientation = null;

      state = state.copyWith(
        isRecording: false,
        isRealtimeOverlayActive: false,
        processingMessage: null,
        videoProcessingError: null,
      );

      if (state.flashMode == FlashMode.always &&
          controller != null &&
          controller.value.isInitialized) {
        await _softFlashQuench(controller);
      }

      final productionDecision =
          await VideoRecordingProductionGate.evaluate(completedSession);
      if (productionDecision.isRejected) {
        throw Exception(productionDecision.reason);
      }

      if (productionDecision.canInstantSave) {
        final now = DateTime.now();
        final rewardKey = 'realtime_${now.microsecondsSinceEpoch}';
        reservedRewardKey = rewardKey;
        ref.read(rewardedCaptureAccessProvider).reserveVideo(rewardKey);
        state = state.copyWith(
          processingMessage: 'Saving recorded video...',
          clearProcessingProgress: true,
        );
        final savedPath = await GallerySaver.saveVideo(lastSegmentPath);
        final savedFile = File(savedPath);
        await ref.read(projectProvider.notifier).assignFileToProject(
              savedFile,
              projectId: completedSession.projectId,
            );
        await ref.read(rewardedCaptureAccessProvider).completeVideo(rewardKey);
        await MediaAuditService.recordVideoSave(
          sourceFiles: completedSession.segments
              .map((segment) => File(segment.path))
              .toList(),
          outputFile: savedFile,
          overlayHistory: completedSession.overlayHistory
              .map((sample) => sample.toJson())
              .toList(),
          durationMs: completedSession.durationMs,
          jobId: rewardKey,
          savedWithoutOverlay: false,
        );
        await ThumbnailUtils.generateVideoThumbnail(savedPath);
        ref.read(galleryFilesProvider.notifier).showFileImmediately(savedFile);
        state = state.copyWith(
          clearProcessingProgress: true,
          processingMessage: 'Video saved instantly.',
          videoProcessingError: null,
        );

        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video saved. Overlay was recorded live.'),
              duration: Duration(milliseconds: 1600),
            ),
          );
        }
        return;
      }

      // Segments that already contain the CameraX overlay are marked below so
      // the fallback worker can merge/mirror them without burning the overlay
      // a second time. Legacy segments still use the original FFmpeg overlay.
      state = state.copyWith(
        processingProgress: 0.05,
        processingMessage: completedSession.segments
                .every((segment) => segment.realtimeOverlayApplied)
            ? 'Finalizing video in background...'
            : 'Processing video in background...',
        videoProcessingError: null,
      );

      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              completedSession.segments
                      .every((segment) => segment.realtimeOverlayApplied)
                  ? 'Finalizing camera segments in background.'
                  : 'Processing video in background. Recording is paused.',
            ),
            duration: const Duration(milliseconds: 2200),
          ),
        );
      }

      final now = DateTime.now();
      final job = VideoProcessingJob(
        id: 'video_${now.microsecondsSinceEpoch}',
        segments: completedSession.segments
            .map((segment) => VideoProcessingSegment(
                  path: segment.path,
                  lens: segment.lens,
                  mirror: segment.mirror,
                  realtimeOverlayApplied: segment.realtimeOverlayApplied,
                  realtimeOverlayHealthy: segment.realtimeOverlayHealthy,
                  containsCameraSwitches: segment.containsCameraSwitches,
                ))
            .toList(),
        history: completedSession.overlayHistory,
        durationMs: completedSession.durationMs,
        createdAtMs: now.millisecondsSinceEpoch,
        projectId: completedSession.projectId,
      );

      reservedRewardKey = job.id;
      ref.read(rewardedCaptureAccessProvider).reserveVideo(job.id);
      await VideoProcessingTaskHandler.enqueueJob(job);
      jobQueuedForProcessing = true;
      await _startForegroundService();
    } catch (e) {
      if (!jobQueuedForProcessing && reservedRewardKey != null) {
        ref.read(rewardedCaptureAccessProvider).failVideo(reservedRewardKey);
      }
      _recordingUsesRewardedFeatures = false;
      _nativeRecordingStarted = false;
      await ref.read(videoRecordingBackendProvider).finishRealtimeOverlay();
      _currentRecordingUsesNativeFrontMirror = false;
      _recordingCaptureOrientation = null;
      debugPrint("Stop recording error: $e");
      final friendlyError = _friendlyStopRecordingError(e);
      state = state.copyWith(
        isRecording: false,
        isRealtimeOverlayActive: false,
        clearProcessingProgress: true,
        processingMessage: jobQueuedForProcessing
            ? 'Video queued for processing.'
            : 'Video recording failed.',
        videoProcessingError: friendlyError,
      );
      _recordingSession.abort();
      if (!jobQueuedForProcessing) {
        await FlutterForegroundTask.stopService();
      }
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
    final ServiceRequestResult result;
    if (isRunning) {
      result = await FlutterForegroundTask.updateService(
        notificationTitle: 'SurveyCam - Media processing',
        notificationText: 'Preparing media...',
        notificationInitialRoute: '/',
      );
    } else {
      result = await FlutterForegroundTask.startService(
        serviceTypes: const [ForegroundServiceTypes.mediaProcessing],
        notificationTitle: 'SurveyCam - Media processing',
        notificationText: 'Preparing media...',
        notificationInitialRoute: '/',
        callback: startCallback,
      );
    }

    if (result is ServiceRequestFailure) {
      await MediaAuditService.recordFailure(
        event: 'video_processing_service_start_failed',
        error: result.error,
        details: {'wasRunning': isRunning},
      );
      throw Exception(
          'Video processing service failed to start: ${result.error}');
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

      final hasPendingVideo = await VideoProcessingTaskHandler.hasPendingJob();
      final hasPendingImage =
          await VideoProcessingTaskHandler.hasPendingImageJob();
      if (!hasPendingVideo && !hasPendingImage) return;

      final serviceWasRunning = await FlutterForegroundTask.isRunningService;
      if (hasPendingVideo) {
        final recoveryReport =
            await VideoProcessingTaskHandler.preparePendingVideoJobsForRestart(
          serviceWasRunning: serviceWasRunning,
        );
        if (!serviceWasRunning && recoveryReport.recoveredInterruptedVideo) {
          final exitInfo = await AppExitInfoService.getLastExitInfo();
          await MediaAuditService.recordFailure(
            event: 'video_processing_recovery_started',
            error: exitInfo?.wasUserRequestedStop == true
                ? 'Previous processing was stopped by Android/user request'
                : 'Previous processing ended before completion',
            details: {
              'pendingVideoJobCount': recoveryReport.pendingVideoJobCount,
              'interruptedVideoJobCount':
                  recoveryReport.interruptedVideoJobCount,
              ...?exitInfo?.toDiagnostics(),
            },
          );
        }

        final message = recoveryReport.recoveredInterruptedVideo
            ? 'Recovering interrupted video processing...'
            : serviceWasRunning
                ? 'Video processing continues in background...'
                : 'Resuming video processing...';
        state = state.copyWith(
          processingProgress: state.processingProgress ?? 0.05,
          processingMessage: message,
          videoProcessingError: null,
        );
        await _startForegroundService();
      } else if (hasPendingImage) {
        await _startForegroundService();
      }
    } catch (e) {
      debugPrint('Pending video resume skipped: $e');
      await MediaAuditService.recordFailure(
        event: 'video_processing_recovery_start_failed',
        error: e,
      );
      if (!mounted) return;
      state = state.copyWith(
        clearProcessingProgress: true,
        processingMessage:
            'Video is queued and will retry when background processing starts.',
        videoProcessingError: _friendlyVideoError(e),
      );
    }
  }

  // ================= DISPOSE =================

  @override
  void dispose() {
    _cancelScheduledZoomFrame();
    _zoomDriveGeneration++;
    _resetExposurePipeline();
    WidgetsBinding.instance.removeObserver(this);
    _recordingSession.abort();
    _recordingCaptureOrientation = null;
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    state = state.copyWith(clearController: true, isReady: false);
    final repository = ref.read(cameraRepositoryProvider);
    unawaited(_sessionQueue.run(repository.dispose));
    super.dispose();
  }
}
