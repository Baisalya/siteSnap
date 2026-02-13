import 'package:camera/camera.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

import '../domain/camera_lens_type.dart';

/// =======================================================
/// ✅ CAMERA STATE
/// =======================================================
class CameraState {
  final bool isReady;
  final CameraController? controller;
  final bool flashOn;
  final CameraLensType currentLens;
  final bool isCapturing;

  /// live orientation from sensor (changes continuously)
  final NativeDeviceOrientation orientation;

  /// frozen orientation at capture moment
  final NativeDeviceOrientation? captureOrientation;

  const CameraState({
    required this.isReady,
    this.controller,
    this.flashOn = false,
    this.currentLens = CameraLensType.normal,
    this.isCapturing = false,
    this.orientation = NativeDeviceOrientation.portraitUp,
    this.captureOrientation,
  });

  CameraState copyWith({
    bool? isReady,
    CameraController? controller,
    bool? flashOn,
    CameraLensType? currentLens,
    bool? isCapturing,
    NativeDeviceOrientation? orientation,
    NativeDeviceOrientation? captureOrientation,
  }) {
    return CameraState(
      isReady: isReady ?? this.isReady,
      controller: controller ?? this.controller,
      flashOn: flashOn ?? this.flashOn,
      currentLens: currentLens ?? this.currentLens,
      isCapturing: isCapturing ?? this.isCapturing,
      orientation: orientation ?? this.orientation,
      captureOrientation:
      captureOrientation ?? this.captureOrientation,
    );
  }
}
