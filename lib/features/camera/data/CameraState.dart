import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import '../../overlay/domain/overlay_model.dart';

import '../domain/camera_lens_type.dart';

enum CameraAspectRatio {
  ratio4_3,
  ratio16_9,
}

enum CameraMode {
  photo,
  video,
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
  final bool isRecording;
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

  final String? error;

  final List<XFile> videoSegments;
  final List<OverlayData> videoDataHistory;
  final double? processingProgress;

  const CameraState({
    required this.isReady,
    this.controller,
    this.flashMode = FlashMode.off,
    this.currentLens = CameraLensType.normal,
    this.isCapturing = false,
    this.isRecording = false,
    this.cameraMode = CameraMode.photo,
    this.isManualFocus = false,
    this.aspectRatio = CameraAspectRatio.ratio16_9,
    this.error,
    this.videoSegments = const [],
    this.videoDataHistory = const [],
    this.processingProgress,
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
    bool? isRecording,
    CameraMode? cameraMode,
    bool? isManualFocus,
    CameraAspectRatio? aspectRatio,
    String? error,
    double? exposure,
    double? minExposure,
    double? maxExposure,
    double? zoom,
    double? maxZoom,
    double? minZoom,
    DeviceOrientation? orientation,
    DeviceOrientation? captureOrientation,
    CameraLensType? captureLens,
    List<XFile>? videoSegments,
    List<OverlayData>? videoDataHistory,
    double? processingProgress,
    bool clearProcessingProgress = false,
  }) {
    return CameraState(
      isReady: isReady ?? this.isReady,
      controller: controller ?? this.controller,
      flashMode: flashMode ?? this.flashMode,
      currentLens: currentLens ?? this.currentLens,
      isCapturing: isCapturing ?? this.isCapturing,
      isRecording: isRecording ?? this.isRecording,
      cameraMode: cameraMode ?? this.cameraMode,
      isManualFocus: isManualFocus ?? this.isManualFocus,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      error: error ?? this.error,
      videoSegments: videoSegments ?? this.videoSegments,
      videoDataHistory: videoDataHistory ?? this.videoDataHistory,
      processingProgress: clearProcessingProgress ? null : (processingProgress ?? this.processingProgress),
      exposure: exposure ?? this.exposure,
      minExposure: minExposure ?? this.minExposure,
      maxExposure: maxExposure ?? this.maxExposure,
      zoom: zoom ?? this.zoom,
      maxZoom: maxZoom ?? this.maxZoom,
      minZoom: minZoom ?? this.minZoom,
      orientation: orientation ?? this.orientation,
      captureOrientation: captureOrientation ?? this.captureOrientation,
      captureLens: captureLens ?? this.captureLens,
    );
  }
}
