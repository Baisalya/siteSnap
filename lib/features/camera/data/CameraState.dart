import 'package:camera/camera.dart' hide CameraLensType;
import 'package:flutter/services.dart';

import '../domain/camera_lens_type.dart';

enum CameraAspectRatio {
  ratio4_3,
  ratio16_9,
}

extension CameraAspectRatioX on CameraAspectRatio {
  double get portraitValue {
    switch (this) {
      case CameraAspectRatio.ratio4_3:
        return 3 / 4;
      case CameraAspectRatio.ratio16_9:
        return 9 / 16;
    }
  }

  double forOrientation(DeviceOrientation orientation) {
    final value = portraitValue;
    switch (orientation) {
      case DeviceOrientation.landscapeLeft:
      case DeviceOrientation.landscapeRight:
        return 1 / value;
      case DeviceOrientation.portraitUp:
      case DeviceOrientation.portraitDown:
        return value;
    }
  }

  String get label {
    switch (this) {
      case CameraAspectRatio.ratio4_3:
        return '3:4';
      case CameraAspectRatio.ratio16_9:
        return '9:16';
    }
  }
}

enum CameraMode {
  photo,
  video,
}

const Object _unsetCameraStateValue = Object();

/// =======================================================
/// ✅ CAMERA STATE
/// =======================================================
class CameraState {
  final bool isReady;
  final CameraController? controller;
  final FlashMode flashMode;
  final CameraLensType currentLens;
  final bool isCapturing;
  final bool isRecording;
  final bool isRealtimeOverlayActive;
  final CameraMode cameraMode;
  final bool isManualFocus;
  final CameraAspectRatio aspectRatio;

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
  final bool captureMirror;

  final String? error;

  final double? processingProgress;
  final String? processingMessage;
  final String? videoProcessingError;

  const CameraState({
    required this.isReady,
    this.controller,
    this.flashMode = FlashMode.off,
    this.currentLens = CameraLensType.normal,
    this.isCapturing = false,
    this.isRecording = false,
    this.isRealtimeOverlayActive = false,
    this.cameraMode = CameraMode.photo,
    this.isManualFocus = false,
    this.aspectRatio = CameraAspectRatio.ratio16_9,
    this.error,
    this.processingProgress,
    this.processingMessage,
    this.videoProcessingError,
    this.exposure = 0.0,
    this.minExposure = -2.0,
    this.maxExposure = 2.0,
    this.zoom = 1.0,
    this.maxZoom = 1.0,
    this.minZoom = 1.0,
    this.orientation = DeviceOrientation.portraitUp,
    this.captureOrientation,
    this.captureLens,
    this.captureMirror = false,
  });

  CameraState copyWith({
    bool? isReady,
    CameraController? controller,
    bool clearController = false,
    FlashMode? flashMode,
    CameraLensType? currentLens,
    bool? isCapturing,
    bool? isRecording,
    bool? isRealtimeOverlayActive,
    CameraMode? cameraMode,
    bool? isManualFocus,
    CameraAspectRatio? aspectRatio,
    Object? error = _unsetCameraStateValue,
    double? exposure,
    double? minExposure,
    double? maxExposure,
    double? zoom,
    double? maxZoom,
    double? minZoom,
    DeviceOrientation? orientation,
    DeviceOrientation? captureOrientation,
    CameraLensType? captureLens,
    bool? captureMirror,
    double? processingProgress,
    bool clearProcessingProgress = false,
    Object? processingMessage = _unsetCameraStateValue,
    Object? videoProcessingError = _unsetCameraStateValue,
  }) {
    return CameraState(
      isReady: isReady ?? this.isReady,
      controller: clearController ? null : (controller ?? this.controller),
      flashMode: flashMode ?? this.flashMode,
      currentLens: currentLens ?? this.currentLens,
      isCapturing: isCapturing ?? this.isCapturing,
      isRecording: isRecording ?? this.isRecording,
      isRealtimeOverlayActive:
          isRealtimeOverlayActive ?? this.isRealtimeOverlayActive,
      cameraMode: cameraMode ?? this.cameraMode,
      isManualFocus: isManualFocus ?? this.isManualFocus,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      error: identical(error, _unsetCameraStateValue)
          ? this.error
          : error as String?,
      processingProgress: clearProcessingProgress
          ? null
          : (processingProgress ?? this.processingProgress),
      processingMessage: identical(processingMessage, _unsetCameraStateValue)
          ? this.processingMessage
          : processingMessage as String?,
      videoProcessingError:
          identical(videoProcessingError, _unsetCameraStateValue)
              ? this.videoProcessingError
              : videoProcessingError as String?,
      exposure: exposure ?? this.exposure,
      minExposure: minExposure ?? this.minExposure,
      maxExposure: maxExposure ?? this.maxExposure,
      zoom: zoom ?? this.zoom,
      maxZoom: maxZoom ?? this.maxZoom,
      minZoom: minZoom ?? this.minZoom,
      orientation: orientation ?? this.orientation,
      captureOrientation: captureOrientation ?? this.captureOrientation,
      captureLens: captureLens ?? this.captureLens,
      captureMirror: captureMirror ?? this.captureMirror,
    );
  }
}
