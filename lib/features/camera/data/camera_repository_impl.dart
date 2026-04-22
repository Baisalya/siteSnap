import 'package:camera/camera.dart';
import '../domain/camera_repository.dart';
import '../domain/camera_lens_type.dart';

class CameraRepositoryImpl implements CameraRepository {
  late CameraController _controller;
  late Map<CameraLensType, CameraDescription> _cameraMap;

  CameraLensType _currentLens = CameraLensType.normal;

  @override
  Future<void> initialize(CameraLensType lens) async {
    final cameras = await availableCameras();

    final backCameras = cameras
        .where((c) => c.lensDirection == CameraLensDirection.back)
        .toList();

    if (backCameras.isEmpty) {
      throw Exception('No back camera found');
    }

    // Usually, the first back camera is the primary one.
    // Some devices have multiple back cameras (Wide, Telephoto, etc.)
    // We try to stick to the primary one for the 'normal' lens.
    final mainCamera = backCameras.first;

    CameraDescription? ultraWide;
    CameraDescription? macro;

    if (backCameras.length > 1) {
      // This is a heuristic, real implementation might need device-specific logic
      // or using a package like camera_android_camerax
      ultraWide = backCameras.last; 
    }

    if (backCameras.length > 2) {
      macro = backCameras[1];
    }

    _cameraMap = {
      CameraLensType.normal: mainCamera,
      if (ultraWide != null)
        CameraLensType.ultraWide: ultraWide,
      if (macro != null)
        CameraLensType.macro: macro,
    };

    _currentLens = lens;

    await _initController(_cameraMap[lens]!);
  }

  Future<void> _initController(CameraDescription camera) async {
    _controller = CameraController(
      camera,
      ResolutionPreset.max, // 🔥 Use HIGH instead of MAX for preview to reduce heat (MAX is overkill for preview)
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await _controller.initialize();

    // Initial quality settings
    await _controller.setFocusMode(FocusMode.auto);
    await _controller.setExposureMode(ExposureMode.auto);
  }

  @override
  Future<String> takePicture() async {
    if (!_controller.value.isInitialized ||
        _controller.value.isTakingPicture) {
      throw Exception("Camera not ready");
    }

    final file = await _controller.takePicture();
    return file.path;
  }

  Future<void> switchLens(CameraLensType type) async {
    if (type == _currentLens) return;
    if (!_cameraMap.containsKey(type)) return;

    await _controller.dispose();

    _currentLens = type;
    await _initController(_cameraMap[type]!);
  }

  CameraLensType get currentLens => _currentLens;

  @override
  CameraController get controller => _controller;
}
