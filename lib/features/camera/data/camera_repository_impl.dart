import 'package:camera/camera.dart';
import 'package:surveycam/features/camera/domain/camera_lens_type.dart';
import 'package:surveycam/features/camera/domain/camera_repository.dart';

class CameraRepositoryImpl implements CameraRepository {
  CameraController? _controller;
  late Map<CameraLensType, CameraDescription> _cameraMap;

  CameraLensType _currentLens = CameraLensType.normal;

  @override
  Future<void> initialize(CameraLensType lens) async {
    // Ensure previous controller is fully disposed before attempting to open a new one
    if (_controller != null) {
      await dispose();
      // Add a small breather for the hardware to release
      await Future.delayed(const Duration(milliseconds: 150));
    }

    final cameras = await availableCameras();

    final backCameras = cameras
        .where((c) => c.lensDirection == CameraLensDirection.back)
        .toList();

    if (backCameras.isEmpty) {
      throw Exception('No back camera found');
    }

    final frontCameras = cameras
        .where((c) => c.lensDirection == CameraLensDirection.front)
        .toList();

    // Usually, the first back camera is the primary one.
    // Some devices have multiple back cameras (Wide, Telephoto, etc.)
    // We try to stick to the primary one for the 'normal' lens.
    final mainCamera = backCameras.first;

    CameraDescription? ultraWide;
    CameraDescription? macro;
    CameraDescription? frontCamera;

    if (backCameras.length > 1) {
      // This is a heuristic, real implementation might need device-specific logic
      // or using a package like camera_android_camerax
      ultraWide = backCameras.last; 
    }

    if (backCameras.length > 2) {
      macro = backCameras[1];
    }

    if (frontCameras.isNotEmpty) {
      frontCamera = frontCameras.first;
    }

    _cameraMap = {
      CameraLensType.normal: mainCamera,
      if (ultraWide != null)
        CameraLensType.ultraWide: ultraWide,
      if (macro != null)
        CameraLensType.macro: macro,
      if (frontCamera != null)
        CameraLensType.front: frontCamera,
    };

    _currentLens = lens;

    final cameraDesc = _cameraMap[lens];
    if (cameraDesc == null) {
      throw Exception('Camera lens not found: $lens');
    }

    await _initController(cameraDesc);
  }

  Future<void> _initController(CameraDescription camera) async {
    final controller = CameraController(
      camera,
      ResolutionPreset.max, // 🔥 Use MAX for highest possible quality
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
          print("Focus mode auto not supported: $e");
        }
        
        try {
          await controller.setExposureMode(ExposureMode.auto);
        } catch (e) {
          print("Exposure mode auto not supported: $e");
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
    if (controller == null || !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      throw Exception("Camera not ready");
    }

    final file = await controller.takePicture();
    return file.path;
  }

  @override
  Future<void> startVideoRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || controller.value.isRecordingVideo) {
      return;
    }
    await controller.startVideoRecording();
  }

  @override
  Future<XFile> stopVideoRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || !controller.value.isRecordingVideo) {
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
        print("Error disposing camera controller: $e");
      }
      _controller = null;
    }
  }

  CameraLensType get currentLens => _currentLens;

  @override
  CameraController? get controller => _controller;
}
