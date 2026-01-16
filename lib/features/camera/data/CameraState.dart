import 'package:camera/camera.dart';

class CameraState {
  final bool isReady;
  final CameraController? controller;
  final bool flashOn;

  CameraState({
    required this.isReady,
    this.controller,
    this.flashOn = false,
  });

  CameraState copyWith({
    bool? isReady,
    CameraController? controller,
    bool? flashOn,
  }) {
    return CameraState(
      isReady: isReady ?? this.isReady,
      controller: controller ?? this.controller,
      flashOn: flashOn ?? this.flashOn,
    );
  }
}
