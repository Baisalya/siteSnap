import 'package:camera/camera.dart';
import '../camera/domain/camera_lens_type.dart';

abstract class CameraRepository {
  Future<void> initialize(CameraLensType lens);
  Future<String> takePicture();
  CameraController get controller;
}
