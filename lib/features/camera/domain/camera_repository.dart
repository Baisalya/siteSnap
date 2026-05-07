import 'package:camera/camera.dart';
import 'camera_lens_type.dart';

abstract class CameraRepository {
  Future<void> initialize(CameraLensType lens);
  Future<String> takePicture();
  Future<void> startVideoRecording();
  Future<XFile> stopVideoRecording();
  CameraController get controller;
}
