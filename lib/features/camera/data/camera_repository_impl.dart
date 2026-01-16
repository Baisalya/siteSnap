import 'package:camera/camera.dart';
import '../../domain/camera_repository.dart';

class CameraRepositoryImpl implements CameraRepository {
  late CameraController _controller;

  @override
  Future<void> initialize() async {
    final cameras = await availableCameras();

    // 1️⃣ Filter BACK cameras only
    final backCameras = cameras
        .where((c) => c.lensDirection == CameraLensDirection.back)
        .toList();

    if (backCameras.isEmpty) {
      throw Exception('No back camera found');
    }

    CameraDescription? bestCamera;
    int maxResolution = 0;

    // 2️⃣ Find camera with highest resolution
    for (final camera in backCameras) {
      final tempController = CameraController(
        camera,
        ResolutionPreset.max,
        enableAudio: false,
      );

      await tempController.initialize();

      final size = tempController.value.previewSize;
      await tempController.dispose();

      if (size != null) {
        final pixels = size.width.toInt() * size.height.toInt();
        if (pixels > maxResolution) {
          maxResolution = pixels;
          bestCamera = camera;
        }
      }
    }

    // 3️⃣ Use BEST camera
    _controller = CameraController(
      bestCamera!,
      ResolutionPreset.max,
      imageFormatGroup: ImageFormatGroup.jpeg,
      enableAudio: false,
    );

    await _controller.initialize();

    // 4️⃣ Optimal settings
    await _controller.setFocusMode(FocusMode.auto);
    await _controller.setExposureMode(ExposureMode.auto);
    await _controller.setZoomLevel(1.0);
    await _controller.setFlashMode(FlashMode.off);
  }

  @override
  Future<String> takePicture() async {
    final file = await _controller.takePicture();
    return file.path;
  }

  @override
  CameraController get controller => _controller;
}
