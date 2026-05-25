import 'package:surveycam/features/camera/domain/camera_lens_type.dart';
import 'package:surveycam/features/overlay/domain/video_overlay_sample.dart';

class VideoProcessingSegment {
  final String path;
  final CameraLensType lens;
  final bool mirror;

  const VideoProcessingSegment({
    required this.path,
    required this.lens,
    this.mirror = false,
  });

  factory VideoProcessingSegment.fromJson(Map<String, dynamic> json) {
    final lens = CameraLensType.values[
        (json['lens'] as int? ?? CameraLensType.normal.index)
            .clamp(0, CameraLensType.values.length - 1)];

    return VideoProcessingSegment(
      path: json['path'] as String? ?? '',
      lens: lens,
      mirror: json['mirror'] as bool? ?? lens == CameraLensType.front,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'lens': lens.index,
      'mirror': mirror,
    };
  }
}

class VideoProcessingJob {
  final String id;
  final List<VideoProcessingSegment> segments;
  final List<VideoOverlaySample> history;
  final int durationMs;
  final int createdAtMs;

  const VideoProcessingJob({
    required this.id,
    required this.segments,
    required this.history,
    required this.durationMs,
    required this.createdAtMs,
  });

  factory VideoProcessingJob.fromJson(Map<String, dynamic> json) {
    return VideoProcessingJob(
      id: json['id'] as String? ?? '',
      segments: (json['segments'] as List? ?? const [])
          .map((item) => VideoProcessingSegment.fromJson(
              Map<String, dynamic>.from(item as Map? ?? const {})))
          .where((segment) => segment.path.isNotEmpty)
          .toList(),
      history: (json['history'] as List? ?? const [])
          .map((item) => VideoOverlaySample.fromJson(
              Map<String, dynamic>.from(item as Map? ?? const {})))
          .toList(),
      durationMs: json['durationMs'] as int? ?? 0,
      createdAtMs: json['createdAtMs'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'segments': segments.map((segment) => segment.toJson()).toList(),
      'history': history.map((sample) => sample.toJson()).toList(),
      'durationMs': durationMs,
      'createdAtMs': createdAtMs,
    };
  }
}
