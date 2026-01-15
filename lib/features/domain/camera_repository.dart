abstract class CameraRepository {
  Future<void> initialize();
  Future<String> takePicture();
}
