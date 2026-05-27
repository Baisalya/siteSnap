import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:surveycam/features/camera/domain/camera_lens_type.dart';
import 'package:surveycam/features/camera/domain/camera_repository.dart';

class CameraRepositoryImpl implements CameraRepository {
  CameraController? _controller;
  late Map<CameraLensType, CameraDescription> _cameraMap;
  List<CameraDescription>? _cachedCameras;

  CameraLensType _currentLens = CameraLensType.normal;

  @override
  Future<void> initialize(CameraLensType lens) async {
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

    // 2. Aggressive Cleanup
    if (_controller != null) {
      try {
        await dispose();
      } catch (e) {
        debugPrint("Cleanup of old controller failed: $e");
      }
      // Reduced breathing room for the OS/Driver to release resources
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // 3. Initialize with Retry Logic
    int retryCount = 0;
    const maxRetries = 2; // Reduced retries for faster failure/recovery

    while (retryCount < maxRetries) {
      try {
        // Proactive Discovery within the retry loop - use cache if available
        final cameras = _cachedCameras ?? await availableCameras();
        _cachedCameras = cameras;

        if (cameras.isEmpty) {
          _cachedCameras = null; // Clear cache on failure to force refresh
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

        // Re-map available lenses based on latest hardware discovery
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
          // If requested lens is gone (e.g. hardware error), fallback to normal back camera
          if (lens != CameraLensType.normal &&
              _cameraMap.containsKey(CameraLensType.normal)) {
            debugPrint(
                "Requested lens $lens not available, falling back to normal");
            await _initController(_cameraMap[CameraLensType.normal]!);
          } else {
            throw Exception('Lens $lens not found and no fallback available');
          }
        } else {
          await _initController(cameraDesc);
        }

        return; // Success!
      } catch (e) {
        retryCount++;
        debugPrint("Camera init attempt $retryCount failed: $e");

        if (retryCount >= maxRetries) rethrow;

        await Future.delayed(Duration(milliseconds: 300 * retryCount));
      }
    }
  }

  Future<void> _initController(CameraDescription camera) async {
    final controller = CameraController(
      camera,
      ResolutionPreset.ultraHigh, // 🔥 Standardize on 4K (UltraHigh) instead of sensor Max
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    _controller = controller;

    try {
      await controller.initialize();

      // Initial quality settings - only if supported
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
      }
    } catch (e) {
      // If initialization fails, dispose and rethrow
      await controller.dispose();
      _controller = null;
      rethrow;
    }
  }

  @override
  Future<String> takePicture() async {
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
  }

  @override
  Future<void> startVideoRecording() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isRecordingVideo) {
      return;
    }
    await controller.startVideoRecording();
  }

  @override
  Future<XFile> stopVideoRecording() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        !controller.value.isRecordingVideo) {
      throw Exception("No recording in progress");
    }
    return await controller.stopVideoRecording();
  }

  Future<void> switchLens(CameraLensType type) async {
    if (type == _currentLens) return;
    if (!_cameraMap.containsKey(type)) return;

    await dispose();

    _currentLens = type;
    await _initController(_cameraMap[type]!);
  }

  @override
  Future<void> dispose() async {
    if (_controller != null) {
      try {
        await _controller!.dispose();
      } catch (e) {
        debugPrint("Error disposing camera controller: $e");
      }
      _controller = null;
    }
  }

  CameraLensType get currentLens => _currentLens;

  @override
  CameraController? get controller => _controller;
}
