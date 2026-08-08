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
import 'package:surveycam/core/services/app_exit_info_service.dart';
import 'package:surveycam/core/services/background_video_task.dart';
import 'package:surveycam/core/services/media_audit_service.dart';
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
import 'package:surveycam/features/overlay/presentation/overlay_viewmodel.dart';
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
  bool _isRestarting = false;
  bool _captureInFlight = false;
  bool _startRecordingInFlight = false;
  bool _stopRecordingInFlight = false;
  Timer? _videoHistoryTimer;
  late final Future<void> _captureDependenciesReady;

  // App lifecycle events can arrive as inactive -> paused -> resumed in quick
  // succession. Keep them serialized so CameraPreview never receives a
  // controller while the repository is disposing the same native session.
  Future<void> _lifecycleQueue = Future<void>.value();
  int _lifecycleGeneration = 0;
  AppLifecycleState _latestLifecycleState = AppLifecycleState.resumed;

  // Optimized overlay history storage
  final List<VideoOverlaySample> _videoDataHistory = [];
  DateTime? _recordingStartTime;
  String? _recordingProjectId;

  bool get isCameraStable => _isCameraStable;
  double get exposureValue => _currentExposure;

  CameraViewModel(this.ref) : super(const CameraState(isReady: false)) {
    WidgetsBinding.instance.addObserver(this);
    // Start plugin/preferences initialization while CameraX is opening so the
    // first shutter press does not pay these one-time costs.
    _captureDependenciesReady = _warmCaptureDependencies();
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

  Future<void> _syncCompletedVideo(Map<String, dynamic> message) async {
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
    await ref.read(projectProvider.notifier).assignFileToProject(
          savedFile,
          projectId: projectId,
          replace: originalFile,
        );
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
    final settings = ref.read(effectiveOverlaySettingsProvider);
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final appState = state;
    _latestLifecycleState = appState;
    final generation = ++_lifecycleGeneration;
    debugPrint("AppLifecycleState: $appState");

    _lifecycleQueue = _lifecycleQueue.catchError((Object error) {
      debugPrint('Previous lifecycle camera operation failed: $error');
    }).then((_) async {
      if (!mounted || generation != _lifecycleGeneration) return;
      await _handleLifecycleState(appState, generation);
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
        if (controller != null && wasRecording) {
          await stopVideoRecordingInBackground();
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

  Future<void> refreshCamera() async {
    debugPrint("Refreshing camera manually...");
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

  Future<void> changeExposure(double delta) async {
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      _currentExposure =
          (_currentExposure + delta).clamp(_minExposure, _maxExposure);

      await _safeCameraCommand(
        controller,
        'exposure offset',
        () => controller.setExposureOffset(_currentExposure),
      );

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
      await _safeCameraCommand(
        controller,
        'zoom level',
        () => controller.setZoomLevel(clampedZoom),
      );
      state = state.copyWith(zoom: clampedZoom);
    } catch (e) {
      debugPrint("Zoom error: $e");
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
  }

  // ================= CAMERA SWITCH =================

  Future<void> switchCamera() async {
    if (_isInitializing ||
        _isRestarting ||
        _startRecordingInFlight ||
        _stopRecordingInFlight) {
      return;
    }

    _isRestarting = true;
    try {
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
        if (controller != null && controller.value.isInitialized) {
          try {
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

            state = state.copyWith(
              isReady: true,
              controller: controller,
              exposure: 0.0,
              minExposure: _minExposure,
              maxExposure: _maxExposure,
              zoom: 1.0,
              minZoom: minZoom ?? state.minZoom,
              maxZoom: maxZoom ?? state.maxZoom,
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
              await _safeCameraCommand(
                controller,
                'switch recording torch',
                () => controller.setFlashMode(FlashMode.torch),
              );
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
    } finally {
      _isRestarting = false;
    }
  }

  // ================= CAPTURE =================

  void setCameraMode(CameraMode mode) {
    state = state.copyWith(cameraMode: mode);
    if (mode == CameraMode.video) {
      unawaited(_prepareVideoForCurrentController());
    }
  }

  Future<void> _prepareVideoForCurrentController() async {
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;
    await _safeCameraCommand(
      controller,
      'video pre-warm',
      controller.prepareForVideoRecording,
    );
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

    final deviceOrientation = ref.read(deviceOrientationProvider);
    state = state.copyWith(
      isCapturing: true,
      captureOrientation: deviceOrientation,
      captureLens: state.currentLens,
    );

    try {
      await _captureDependenciesReady;
      if (!_isActiveController(controller)) return null;

      final overlayData = ref.read(overlayPreviewProvider);
      ref.read(capturedOverlayProvider.notifier).state = overlayData;

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
          await _safeCameraCommand(
            controller,
            'capture torch on',
            () => controller.setFlashMode(FlashMode.torch),
          );
          await Future.delayed(_flashExposureSettleDelay);
        }
      }

      // Actual capture - native speed is controlled by the camera plugin/driver
      final path = await repo.takePicture().timeout(_photoCaptureTimeout);

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
      // Restore under the camera queue. Do not leave flash/focus cleanup running
      // unawaited after a capture because it can race a fast back/resume/dispose.
      _captureInFlight = false;
      await _restoreCameraState(controller);
      state = state.copyWith(isCapturing: false);
    }
  }

  Future<bool> capturePhotoDuringRecording() async {
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
    final deviceOrientation = ref.read(deviceOrientationProvider);
    final captureLens = state.currentLens;
    final aspectRatio = state.aspectRatio;

    state = state.copyWith(
      isCapturing: true,
      captureOrientation: deviceOrientation,
      captureLens: captureLens,
    );

    try {
      final repo = ref.read(cameraRepositoryProvider);
      final path = await repo.takePicture().timeout(_photoCaptureTimeout);
      final originalFile = File(path);

      await ref.read(overlayViewModelProvider.notifier).saveCapturedImage(
            original: originalFile,
            orientation: deviceOrientation,
            overlayData: overlayData,
            showOverlay: true,
            showWatermark: true,
            aspectRatio: aspectRatio,
            mirror: captureLens == CameraLensType.front,
            settingsOverride: overlaySettings,
          );

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

  Future<void> _prepareSmartPhotoExposure(CameraController controller) async {
    try {
      if (!_isActiveController(controller)) return;

      if (!state.isManualFocus) {
        await _safeCameraCommand(
          controller,
          'photo exposure auto',
          () => controller.setExposureMode(ExposureMode.auto),
        );
        await _safeCameraCommand(
          controller,
          'photo focus auto',
          () => controller.setFocusMode(FocusMode.auto),
        );
        await _safeCameraCommand(
          controller,
          'photo exposure point',
          () => controller.setExposurePoint(const Offset(0.5, 0.5)),
        );
        await _safeCameraCommand(
          controller,
          'photo focus point',
          () => controller.setFocusPoint(const Offset(0.5, 0.5)),
        );
      }

      if (_currentExposure != 0.0) {
        await _safeCameraCommand(
          controller,
          'photo exposure offset',
          () => controller.setExposureOffset(
            _currentExposure.clamp(_minExposure, _maxExposure),
          ),
        );
      }
    } catch (e) {
      debugPrint("Smart exposure preparation skipped: $e");
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

      if (state.isManualFocus) {
        await _safeCameraCommand(
          controller,
          'restore focus auto',
          () => controller.setFocusMode(FocusMode.auto),
        );
        await _safeCameraCommand(
          controller,
          'restore exposure auto',
          () => controller.setExposureMode(ExposureMode.auto),
        );
        await _safeCameraCommand(
          controller,
          'restore focus point',
          () => controller.setFocusPoint(null),
        );
        await _safeCameraCommand(
          controller,
          'restore exposure point',
          () => controller.setExposurePoint(null),
        );
      }

      if (_currentExposure != 0.0) {
        await _safeCameraCommand(
          controller,
          'restore exposure offset',
          () => controller.setExposureOffset(_currentExposure),
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
        await _safeCameraCommand(
          controller,
          'start recording torch',
          () => controller.setFlashMode(FlashMode.torch),
        );
      }

      await repo.startVideoRecording();

      // The app can be backgrounded while CameraX is asynchronously creating
      // the recorder. Do not publish a recording state for a controller that
      // the lifecycle handler has already hidden or queued for disposal.
      if (!mounted ||
          _isDisposing ||
          _latestLifecycleState != AppLifecycleState.resumed ||
          !_isActiveController(controller)) {
        debugPrint('Recording start completed after camera became inactive');
        return false;
      }

      // Start history tracking
      _videoHistoryTimer?.cancel();
      if (clearSegments || state.videoSegments.isEmpty) {
        _videoDataHistory.clear();
        await ref.read(projectProvider.notifier).ready;
        await ref.read(overlaySettingsProvider.notifier).ready;
        _recordingProjectId = ref.read(effectiveActiveProjectIdProvider);
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

    // Claim the stop before awaiting CameraX's recorder stabilization delay so
    // a second tap or lifecycle callback cannot enter another stop operation.
    _stopRecordingInFlight = true;
    var jobQueuedForProcessing = false;
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
          settings: ref.read(effectiveOverlaySettingsProvider),
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
        projectId: _recordingProjectId,
      );

      await VideoProcessingTaskHandler.enqueueJob(job);
      jobQueuedForProcessing = true;
      await _startForegroundService();

      state = state.copyWith(
        videoSegments: [],
        videoSequenceDir: null,
      );
      _videoDataHistory.clear();
      _recordingStartTime = null;
      _recordingProjectId = null;
    } catch (e) {
      debugPrint("Stop recording error: $e");
      final friendlyError = _friendlyStopRecordingError(e);
      state = state.copyWith(
        isRecording: false,
        clearProcessingProgress: true,
        videoSegments: [],
        videoSequenceDir: null,
        processingMessage: jobQueuedForProcessing
            ? 'Video queued for processing.'
            : 'Video recording failed.',
        videoProcessingError: friendlyError,
      );
      _videoHistoryTimer?.cancel();
      _videoHistoryTimer = null;
      _videoDataHistory.clear();
      _recordingStartTime = null;
      _recordingProjectId = null;
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
    WidgetsBinding.instance.removeObserver(this);
    _videoHistoryTimer?.cancel();
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    state = state.copyWith(clearController: true, isReady: false);
    unawaited(ref.read(cameraRepositoryProvider).dispose());
    super.dispose();
  }
}
