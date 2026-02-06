import 'package:camera/camera.dart';
import '../../domain/camera_repository.dart';
import '../domain/camera_lens_type.dart';

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

    final backCameras =
    cameras.where((c) => c.lensDirection == CameraLensDirection.back).toList();

    if (backCameras.isEmpty) {
      throw Exception('No back camera found');
    }

    // ✅ DO NOT sort by sensorOrientation
    // Android already orders cameras by priority (OEM standard)

    _cameraMap = {
      CameraLensType.normal: backCameras.first,
      if (backCameras.length > 1)
        CameraLensType.ultraWide: backCameras[1],
      if (backCameras.length > 2)
        CameraLensType.macro: backCameras.last,
    };

    _currentLens = lens;
    await _initController(_cameraMap[lens]!);
  }

  Future<void> _initController(CameraDescription camera) async {
    _controller = CameraController(
      camera,
      ResolutionPreset.veryHigh, // ✅ highest possible
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await _controller.initialize();

    // Quality tweaks
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
