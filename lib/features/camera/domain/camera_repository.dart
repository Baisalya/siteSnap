import 'package:camera/camera.dart' hide CameraLensType;
import 'camera_lens_type.dart';

abstract class CameraRepository {
  Future<void> initialize(CameraLensType lens);
  Future<String> takePicture();
  Future<void> startVideoRecording();
  Future<XFile> stopVideoRecording();
  Future<void> dispose();
  CameraController? get controller;
}
