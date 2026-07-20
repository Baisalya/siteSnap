import 'dart:async';

import 'package:camera/camera.dart' hide CameraLensType;
import 'package:flutter/foundation.dart';
import 'package:surveycam/features/camera/domain/camera_lens_type.dart';
import 'package:surveycam/features/camera/domain/camera_repository.dart';

class CameraRepositoryImpl implements CameraRepository {
  CameraController? _controller;
  late Map<CameraLensType, CameraDescription> _cameraMap;
  List<CameraDescription>? _cachedCameras;

  CameraLensType _currentLens = CameraLensType.normal;

  /// Serializes every CameraX/native operation. The Android camera plugin is
  /// sensitive to overlapping initialize/dispose/flash/focus/capture calls and
  /// can crash in native Pigeon/FlutterJNI code when calls race with lifecycle
  /// teardown. ViewModels can also use this for direct controller commands.
  Future<void> _cameraOperationQueue = Future<void>.value();

  Future<T> runExclusive<T>(Future<T> Function() action) {
    final previous = _cameraOperationQueue.catchError((Object error) {
      debugPrint('Previous camera operation failed before queue continued: $error');
    });
    final completer = Completer<T>();

    _cameraOperationQueue = previous.then((_) async {
      try {
        final value = await action();
        if (!completer.isCompleted) completer.complete(value);
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    });

    return completer.future;
  }

  @override
  Future<void> initialize(CameraLensType lens) {
    return runExclusive(() => _initializeInternal(lens));
  }

  Future<void> _initializeInternal(CameraLensType lens) async {
    // 1. If we are already initialized with the correct lens, perform a health check
    if (_controller != null &&
        _controller!.value.isInitialized &&
        _currentLens == lens) {
      try {
        // Health check: if preview is paused, just resume it
        if (!_controller!.value.isPreviewPaused) {
          await _controller!.getMinZoomLevel();
        }
        return;
      } catch (e) {
        debugPrint(
            "Camera hardware health check failed: $e. Re-initializing...");
      }
    }

    // 2. Aggressive cleanup, but inside the same queue to avoid dispose/init races.
    if (_controller != null) {
      try {
        await _disposeInternal();
      } catch (e) {
        debugPrint("Cleanup of old controller failed: $e");
      }
      // Breathing room for CameraX/driver to release native resources.
      await Future.delayed(const Duration(milliseconds: 350));
    }

    // 3. Initialize with bounded retry logic.
    int retryCount = 0;
    const maxRetries = 2;

    while (retryCount < maxRetries) {
      try {
        final cameras = _cachedCameras ?? await availableCameras();
        _cachedCameras = cameras;

        if (cameras.isEmpty) {
          _cachedCameras = null;
          throw Exception('No cameras detected on this device');
        }

        final backCameras = cameras
            .where((c) => c.lensDirection == CameraLensDirection.back)
            .toList();

        final frontCameras = cameras
            .where((c) => c.lensDirection == CameraLensDirection.front)
            .toList();

        if (backCameras.isEmpty && frontCameras.isEmpty) {
          throw Exception('No usable camera lenses found');
        }

        final Map<CameraLensType, CameraDescription> newMap = {};

        if (backCameras.isNotEmpty) {
          newMap[CameraLensType.normal] = backCameras.first;
          if (backCameras.length > 1) {
            newMap[CameraLensType.ultraWide] = backCameras.last;
          }
          if (backCameras.length > 2) {
            newMap[CameraLensType.macro] = backCameras[1];
          }
        }

        if (frontCameras.isNotEmpty) {
          newMap[CameraLensType.front] = frontCameras.first;
        }

        _cameraMap = newMap;
        _currentLens = lens;

        final cameraDesc = _cameraMap[lens];
        if (cameraDesc == null) {
          if (lens != CameraLensType.normal &&
              _cameraMap.containsKey(CameraLensType.normal)) {
            debugPrint(
                "Requested lens $lens not available, falling back to normal");
            _currentLens = CameraLensType.normal;
            await _initController(_cameraMap[CameraLensType.normal]!);
          } else {
            throw Exception('Lens $lens not found and no fallback available');
          }
        } else {
          await _initController(cameraDesc);
        }

        return;
      } catch (e) {
        retryCount++;
        debugPrint("Camera init attempt $retryCount failed: $e");

        if (retryCount >= maxRetries) rethrow;

        await Future.delayed(Duration(milliseconds: 350 * retryCount));
      }
    }
  }

  Future<void> _initController(CameraDescription camera) async {
    // Fewer resolution attempts reduce native churn on devices with fragile
    // CameraX sessions while still keeping high quality for release users.
    final resolutions = [
      ResolutionPreset.veryHigh,
      ResolutionPreset.high,
      ResolutionPreset.medium,
    ];

    Object? lastError;

    for (final resolution in resolutions) {
      final controller = CameraController(
        camera,
        resolution,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      _controller = controller;

      try {
        await controller.initialize();

        if (controller.value.isInitialized) {
          try {
            await controller.setFocusMode(FocusMode.auto);
          } catch (e) {
            debugPrint("Focus mode auto not supported: $e");
          }

          try {
            await controller.setExposureMode(ExposureMode.auto);
          } catch (e) {
            debugPrint("Exposure mode auto not supported: $e");
          }

          debugPrint("Camera initialized successfully with $resolution");
          return;
        }
      } catch (e) {
        lastError = e;
        debugPrint("Camera initialization failed with $resolution: $e");
        try {
          await controller.dispose();
        } catch (disposeError) {
          debugPrint("Controller dispose after failed init skipped: $disposeError");
        }
        if (_controller == controller) {
          _controller = null;
        }
      }
    }

    if (lastError != null) {
      throw lastError;
    }
    throw Exception('Failed to initialize camera with any resolution preset');
  }

  @override
  Future<String> takePicture() {
    return runExclusive(() async {
      final controller = _controller;
      if (controller == null ||
          !controller.value.isInitialized ||
          controller.value.isTakingPicture) {
        throw Exception("Camera not ready");
      }

      if (controller.value.isPreviewPaused) {
        await controller.resumePreview();
      }

      final file = await controller.takePicture();
      return file.path;
    });
  }

  @override
  Future<void> startVideoRecording() {
    return runExclusive(() async {
      final controller = _controller;
      if (controller == null ||
          !controller.value.isInitialized ||
          controller.value.isRecordingVideo) {
        return;
      }
      try {
        await controller.startVideoRecording();
      } catch (e) {
        debugPrint("Error starting video recording: $e");
        rethrow;
      }
    });
  }

  @override
  Future<XFile> stopVideoRecording() {
    return runExclusive(() async {
      final controller = _controller;
      if (controller == null ||
          !controller.value.isInitialized ||
          !controller.value.isRecordingVideo) {
        throw Exception("No recording in progress");
      }
      try {
        return await controller.stopVideoRecording();
      } catch (e) {
        debugPrint("Error stopping video recording: $e");
        rethrow;
      }
    });
  }

  Future<void> switchLens(CameraLensType type) {
    return runExclusive(() async {
      if (type == _currentLens) return;
      if (!_cameraMap.containsKey(type)) return;

      await _disposeInternal();
      await Future.delayed(const Duration(milliseconds: 250));

      _currentLens = type;
      await _initController(_cameraMap[type]!);
    });
  }

  @override
  Future<void> dispose() {
    return runExclusive(_disposeInternal);
  }

  Future<void> _disposeInternal() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (e) {
        debugPrint("Error disposing camera controller: $e");
      }
    }
  }

  CameraLensType get currentLens => _currentLens;

  @override
  CameraController? get controller => _controller;
}
