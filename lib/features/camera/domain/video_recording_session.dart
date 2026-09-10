import 'package:surveycam/features/camera/domain/camera_lens_type.dart';
import 'package:surveycam/features/overlay/domain/video_overlay_sample.dart';

class VideoRecordingSegment {
  final String path;
  final CameraLensType lens;
  final bool mirror;
  final bool realtimeOverlayApplied;
  final bool realtimeOverlayHealthy;

  /// True when this single native file contains one or more persistent
  /// front/back lens changes. This prevents legacy front-only orientation
  /// correction from being incorrectly applied to the whole mixed-lens file.
  final bool containsCameraSwitches;

  const VideoRecordingSegment({
    required this.path,
    required this.lens,
    this.mirror = false,
    this.realtimeOverlayApplied = false,
    bool? realtimeOverlayHealthy,
    this.containsCameraSwitches = false,
  }) : realtimeOverlayHealthy =
            realtimeOverlayHealthy ?? realtimeOverlayApplied;
}

class CompletedVideoRecordingSession {
  final List<VideoRecordingSegment> segments;
  final List<VideoOverlaySample> overlayHistory;
  final int durationMs;
  final String? projectId;

  const CompletedVideoRecordingSession({
    required this.segments,
    required this.overlayHistory,
    required this.durationMs,
    required this.projectId,
  });
}
