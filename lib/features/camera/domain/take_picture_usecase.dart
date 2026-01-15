import '../../domain/camera_repository.dart';
import 'camera_repository.dart';

class TakePictureUseCase {
  final CameraRepository repository;

  TakePictureUseCase(this.repository);

  Future<String> execute() async {
    return await repository.takePicture();
  }
}
