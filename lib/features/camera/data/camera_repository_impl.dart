import 'package:camera/camera.dart';
import '../../domain/camera_repository.dart';

class CameraRepositoryImpl implements CameraRepository {
  late CameraController _controller;

  @override
  Future<void> initialize() async {
    final cameras = await availableCameras();
    _controller = CameraController(
      cameras.first,
      ResolutionPreset.max,
      enableAudio: false,
    );
    await _controller.initialize();
  }

  @override
  Future<String> takePicture() async {
    final file = await _controller.takePicture();
    return file.path;
  }

  CameraController get controller => _controller;
}
