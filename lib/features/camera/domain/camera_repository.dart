import 'package:camera/camera.dart' hide CameraLensType;
import 'camera_lens_type.dart';

abstract class CameraRepository {
  Future<void> initialize(CameraLensType lens);
  Future<String> takePicture();
  Future<void> startVideoRecording();
  Future<XFile> stopVideoRecording();

  /// Switches the active CameraX camera without stopping a persistent video.
  /// Returns false when the current platform/session cannot preserve recording.
  Future<bool> switchLensWhileRecording(CameraLensType lens);
  Future<void> dispose();
  CameraController? get controller;
}
