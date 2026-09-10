import 'dart:io';

import 'package:surveycam/features/camera/domain/video_recording_session.dart';

enum VideoFinalizationRoute {
  instantSave,
  backgroundFinalize,
  reject,
}

class VideoRecordingProductionDecision {
  final VideoFinalizationRoute route;
  final String reason;

  const VideoRecordingProductionDecision(this.route, this.reason);

  bool get canInstantSave => route == VideoFinalizationRoute.instantSave;
  bool get isRejected => route == VideoFinalizationRoute.reject;
}

/// Fail-closed production gate between CameraX finalization and Gallery save.
///
/// It verifies that every finalized temporary segment actually exists and is
/// non-empty before choosing an instant-save or background-finalization route.
class VideoRecordingProductionGate {
  const VideoRecordingProductionGate._();

  static Future<VideoRecordingProductionDecision> evaluate(
    CompletedVideoRecordingSession session,
  ) async {
    if (session.segments.isEmpty) {
      return const VideoRecordingProductionDecision(
        VideoFinalizationRoute.reject,
        'No finalized video segment was produced.',
      );
    }

    for (final segment in session.segments) {
      if (segment.path.trim().isEmpty) {
        return const VideoRecordingProductionDecision(
          VideoFinalizationRoute.reject,
          'Camera returned an empty video path.',
        );
      }
      final file = File(segment.path);
      try {
        if (!await file.exists() || await file.length() <= 0) {
          return VideoRecordingProductionDecision(
            VideoFinalizationRoute.reject,
            'Finalized video segment is missing or empty: ${segment.path}',
          );
        }
      } on FileSystemException {
        return VideoRecordingProductionDecision(
          VideoFinalizationRoute.reject,
          'Finalized video segment cannot be read: ${segment.path}',
        );
      }
    }

    final single =
        session.segments.length == 1 ? session.segments.single : null;
    if (single != null &&
        single.realtimeOverlayApplied &&
        single.realtimeOverlayHealthy &&
        !single.mirror) {
      return const VideoRecordingProductionDecision(
        VideoFinalizationRoute.instantSave,
        'Verified CameraX realtime segment can be saved directly.',
      );
    }

    return const VideoRecordingProductionDecision(
      VideoFinalizationRoute.backgroundFinalize,
      'Segment merge, transform, or conservative realtime verification required.',
    );
  }
}
