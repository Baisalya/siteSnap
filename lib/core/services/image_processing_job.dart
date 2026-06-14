import 'package:flutter/services.dart';
import 'package:surveycam/features/camera/data/CameraState.dart';
import 'package:surveycam/features/overlay/domain/overlay_model.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';

class ImageProcessingJob {
  final String id;
  final String originalPath;
  final OverlayData overlayData;
  final DeviceOrientation orientation;
  final OverlaySettings settings;
  final bool showOverlay;
  final bool showWatermark;
  final CameraAspectRatio? aspectRatio;
  final bool mirror;
  final int createdAtMs;
  final String? projectId;

  const ImageProcessingJob({
    required this.id,
    required this.originalPath,
    required this.overlayData,
    required this.orientation,
    required this.settings,
    required this.showOverlay,
    required this.showWatermark,
    required this.aspectRatio,
    required this.mirror,
    required this.createdAtMs,
    this.projectId,
  });

  factory ImageProcessingJob.fromJson(Map<String, dynamic> json) {
    final aspectRatioIndex = json['aspectRatio'] as int?;

    return ImageProcessingJob(
      id: json['id'] as String? ?? '',
      originalPath: json['originalPath'] as String? ?? '',
      overlayData: OverlayData.fromJson(
        Map<String, dynamic>.from(json['overlayData'] as Map? ?? const {}),
      ),
      orientation: DeviceOrientation.values[
          (json['orientation'] as int? ?? DeviceOrientation.portraitUp.index)
              .clamp(0, DeviceOrientation.values.length - 1)],
      settings: OverlaySettings.fromJson(
        Map<String, dynamic>.from(json['settings'] as Map? ?? const {}),
      ),
      showOverlay: json['showOverlay'] as bool? ?? true,
      showWatermark: json['showWatermark'] as bool? ?? true,
      aspectRatio: aspectRatioIndex == null
          ? null
          : CameraAspectRatio.values[
              aspectRatioIndex.clamp(0, CameraAspectRatio.values.length - 1)],
      mirror: json['mirror'] as bool? ?? false,
      createdAtMs: json['createdAtMs'] as int? ?? 0,
      projectId: json['projectId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'originalPath': originalPath,
      'overlayData': overlayData.toJson(),
      'orientation': orientation.index,
      'settings': settings.toJson(),
      'showOverlay': showOverlay,
      'showWatermark': showWatermark,
      'aspectRatio': aspectRatio?.index,
      'mirror': mirror,
      'createdAtMs': createdAtMs,
      'projectId': projectId,
    };
  }
}
