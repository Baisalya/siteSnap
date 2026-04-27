import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import '../domain/camera_lens_type.dart';

enum CameraAspectRatio {
  ratio4_3,
  ratio16_9,
}

/// =======================================================
/// ✅ CAMERA STATE
/// =======================================================
class CameraState {
  final bool isReady;
  final CameraController? controller;
  final FlashMode flashMode;
  final CameraLensType currentLens;
  final bool isCapturing;
  final bool isManualFocus;
  final CameraAspectRatio aspectRatio;

  /// 🔥 ADD THIS
  final double exposure;
  final double minExposure;
  final double maxExposure;
  final double zoom;
  final double maxZoom;
  final double minZoom;

  /// live orientation from sensor
  final DeviceOrientation orientation;

  /// frozen orientation at capture moment
  final DeviceOrientation? captureOrientation;
  final CameraLensType? captureLens;

  final String? error;

  const CameraState({
    required this.isReady,
    this.controller,
    this.flashMode = FlashMode.off,
    this.currentLens = CameraLensType.normal,
    this.isCapturing = false,
    this.isManualFocus = false,
    this.aspectRatio = CameraAspectRatio.ratio16_9,
    this.error,

    /// 🔥 DEFAULT
    this.exposure = 0.0,
    this.minExposure = -2.0,
    this.maxExposure = 2.0,
    this.zoom = 1.0,
    this.maxZoom = 1.0,
    this.minZoom = 1.0,

    this.orientation = DeviceOrientation.portraitUp,
    this.captureOrientation,
    this.captureLens,
  });

  CameraState copyWith({
    bool? isReady,
    CameraController? controller,
    FlashMode? flashMode,
    CameraLensType? currentLens,
    bool? isCapturing,
    bool? isManualFocus,
    CameraAspectRatio? aspectRatio,
    String? error,

    /// 🔥 ADD THIS
    double? exposure,
    double? minExposure,
    double? maxExposure,
    double? zoom,
    double? maxZoom,
    double? minZoom,

    DeviceOrientation? orientation,
    DeviceOrientation? captureOrientation,
    CameraLensType? captureLens,
  }) {
    return CameraState(
      isReady: isReady ?? this.isReady,
      controller: controller ?? this.controller,
      flashMode: flashMode ?? this.flashMode,
      currentLens: currentLens ?? this.currentLens,
      isCapturing: isCapturing ?? this.isCapturing,
      isManualFocus: isManualFocus ?? this.isManualFocus,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      error: error ?? this.error,

      /// 🔥 APPLY
    exposure: exposure ?? this.exposure,
    minExposure: minExposure ?? this.minExposure,
    maxExposure: maxExposure ?? this.maxExposure,
    zoom: zoom ?? this.zoom,
    maxZoom: maxZoom ?? this.maxZoom,
    minZoom: minZoom ?? this.minZoom,

      orientation: orientation ?? this.orientation,
      captureOrientation:
      captureOrientation ?? this.captureOrientation,
      captureLens: captureLens ?? this.captureLens,
    );
  }
}
