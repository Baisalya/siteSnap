import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

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

  /// 🔥 ADD THIS
  final double exposure;

  /// live orientation from sensor
  final DeviceOrientation orientation;

  /// frozen orientation at capture moment
  final DeviceOrientation? captureOrientation;

  final String? error;

  const CameraState({
    required this.isReady,
    this.controller,
    this.flashOn = false,
    this.currentLens = CameraLensType.normal,
    this.isCapturing = false,
    this.error,

    /// 🔥 DEFAULT
    this.exposure = 0.0,

    this.orientation = DeviceOrientation.portraitUp,
    this.captureOrientation,
  });

  CameraState copyWith({
    bool? isReady,
    CameraController? controller,
    bool? flashOn,
    CameraLensType? currentLens,
    bool? isCapturing,
    String? error,

    /// 🔥 ADD THIS
    double? exposure,

    DeviceOrientation? orientation,
    DeviceOrientation? captureOrientation,
  }) {
    return CameraState(
      isReady: isReady ?? this.isReady,
      controller: controller ?? this.controller,
      flashOn: flashOn ?? this.flashOn,
      currentLens: currentLens ?? this.currentLens,
      isCapturing: isCapturing ?? this.isCapturing,
      error: error ?? this.error,

      /// 🔥 APPLY
      exposure: exposure ?? this.exposure,

      orientation: orientation ?? this.orientation,
      captureOrientation:
      captureOrientation ?? this.captureOrientation,
    );
  }
}