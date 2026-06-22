import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/core/services/image_processing_job.dart';
import 'package:surveycam/features/camera/data/CameraState.dart';
import 'package:surveycam/features/overlay/domain/WatermarkPosition.dart';
import 'package:surveycam/features/overlay/domain/overlay_model.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';

const _overlayData = OverlayData(
  dateTime: '2026-06-19 10:30',
  latitude: 22.57,
  longitude: 88.36,
  altitude: 12,
  heading: 90,
  direction: 'E',
  note: 'Gate photo',
  position: WatermarkPosition.bottomRight,
);

void main() {
  test('image job preserves direct-save watermark capture settings', () {
    final job = ImageProcessingJob(
      id: 'recording_photo_1',
      originalPath: 'cache/capture.jpg',
      overlayData: _overlayData,
      orientation: DeviceOrientation.landscapeLeft,
      settings: const OverlaySettings(),
      showOverlay: true,
      showWatermark: true,
      aspectRatio: CameraAspectRatio.ratio4_3,
      mirror: true,
      createdAtMs: 42,
      projectId: 'project-1',
    );

    final roundTrip = ImageProcessingJob.fromJson(job.toJson());

    expect(roundTrip.id, job.id);
    expect(roundTrip.originalPath, job.originalPath);
    expect(roundTrip.overlayData.position, WatermarkPosition.bottomRight);
    expect(roundTrip.orientation, DeviceOrientation.landscapeLeft);
    expect(roundTrip.showOverlay, isTrue);
    expect(roundTrip.showWatermark, isTrue);
    expect(roundTrip.aspectRatio, CameraAspectRatio.ratio4_3);
    expect(roundTrip.mirror, isTrue);
    expect(roundTrip.projectId, 'project-1');
  });
}
