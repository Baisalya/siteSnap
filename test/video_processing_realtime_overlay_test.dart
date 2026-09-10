import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/core/services/video_processing_job.dart';
import 'package:surveycam/features/camera/domain/camera_lens_type.dart';

void main() {
  test('realtime overlay segment survives queue JSON round trip', () {
    const segment = VideoProcessingSegment(
      path: '/tmp/segment.mp4',
      lens: CameraLensType.normal,
      realtimeOverlayApplied: true,
      realtimeOverlayHealthy: false,
      containsCameraSwitches: true,
    );

    final restored = VideoProcessingSegment.fromJson(segment.toJson());

    expect(restored.path, segment.path);
    expect(restored.lens, segment.lens);
    expect(restored.realtimeOverlayApplied, isTrue);
    expect(restored.realtimeOverlayHealthy, isFalse);
    expect(restored.containsCameraSwitches, isTrue);
  });

  test('legacy queued segment defaults realtime overlay marker to false', () {
    final restored = VideoProcessingSegment.fromJson(
      <String, dynamic>{
        'path': '/tmp/legacy.mp4',
        'lens': CameraLensType.normal.index,
        'mirror': false,
      },
    );

    expect(restored.realtimeOverlayApplied, isFalse);
    expect(restored.realtimeOverlayHealthy, isFalse);
    expect(restored.containsCameraSwitches, isFalse);
  });
}
