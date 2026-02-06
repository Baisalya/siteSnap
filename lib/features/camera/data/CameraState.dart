import 'package:camera/camera.dart';

class CameraState {
  final bool isReady;
  final CameraController? controller;
  final bool flashOn;
  final bool isCapturing;

  CameraState({
    required this.isReady,
    this.controller,
    this.flashOn = false,
    this.isCapturing = false,
  });

  CameraState copyWith({
    bool? isReady,
    CameraController? controller,
    bool? flashOn,
    bool? isCapturing,

  }) {
    return CameraState(
      isReady: isReady ?? this.isReady,
      controller: controller ?? this.controller,
      flashOn: flashOn ?? this.flashOn,
      isCapturing: isCapturing ?? this.isCapturing,

    );
  }
}
