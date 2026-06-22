import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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

  VideoProcessingSegment copyWith({
    String? path,
    CameraLensType? lens,
    bool? mirror,
  }) {
    return VideoProcessingSegment(
      path: path ?? this.path,
      lens: lens ?? this.lens,
      mirror: mirror ?? this.mirror,
    );
  }

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
  final String? projectId;
  final int attemptCount;
  final int? lastAttemptAtMs;
  final String? lastError;
  final int interruptionCount;
  final int? lastInterruptedAtMs;

  const VideoProcessingJob({
    required this.id,
    required this.segments,
    required this.history,
    required this.durationMs,
    required this.createdAtMs,
    this.projectId,
    this.attemptCount = 0,
    this.lastAttemptAtMs,
    this.lastError,
    this.interruptionCount = 0,
    this.lastInterruptedAtMs,
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
      projectId: json['projectId'] as String?,
      attemptCount: json['attemptCount'] as int? ?? 0,
      lastAttemptAtMs: json['lastAttemptAtMs'] as int?,
      lastError: json['lastError'] as String?,
      interruptionCount: json['interruptionCount'] as int? ?? 0,
      lastInterruptedAtMs: json['lastInterruptedAtMs'] as int?,
    );
  }

  VideoProcessingJob copyWith({
    String? id,
    List<VideoProcessingSegment>? segments,
    List<VideoOverlaySample>? history,
    int? durationMs,
    int? createdAtMs,
    String? projectId,
    int? attemptCount,
    Object? lastAttemptAtMs = _unsetVideoProcessingJobValue,
    Object? lastError = _unsetVideoProcessingJobValue,
    int? interruptionCount,
    Object? lastInterruptedAtMs = _unsetVideoProcessingJobValue,
  }) {
    return VideoProcessingJob(
      id: id ?? this.id,
      segments: segments ?? this.segments,
      history: history ?? this.history,
      durationMs: durationMs ?? this.durationMs,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      projectId: projectId ?? this.projectId,
      attemptCount: attemptCount ?? this.attemptCount,
      lastAttemptAtMs: identical(lastAttemptAtMs, _unsetVideoProcessingJobValue)
          ? this.lastAttemptAtMs
          : lastAttemptAtMs as int?,
      lastError: identical(lastError, _unsetVideoProcessingJobValue)
          ? this.lastError
          : lastError as String?,
      interruptionCount: interruptionCount ?? this.interruptionCount,
      lastInterruptedAtMs:
          identical(lastInterruptedAtMs, _unsetVideoProcessingJobValue)
              ? this.lastInterruptedAtMs
              : lastInterruptedAtMs as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'segments': segments.map((segment) => segment.toJson()).toList(),
      'history': history.map((sample) => sample.toJson()).toList(),
      'durationMs': durationMs,
      'createdAtMs': createdAtMs,
      'projectId': projectId,
      'attemptCount': attemptCount,
      'lastAttemptAtMs': lastAttemptAtMs,
      'lastError': lastError,
      'interruptionCount': interruptionCount,
      'lastInterruptedAtMs': lastInterruptedAtMs,
    };
  }
}

const Object _unsetVideoProcessingJobValue = Object();

class VideoProcessingJobQueue {
  const VideoProcessingJobQueue._();

  static List<VideoProcessingJob> decode(
    String? queueJson, {
    String? legacyJobJson,
  }) {
    final jobs = <VideoProcessingJob>[];

    void addJob(VideoProcessingJob job) {
      if (job.id.isEmpty || jobs.any((existing) => existing.id == job.id)) {
        return;
      }
      jobs.add(job);
    }

    try {
      if (queueJson != null && queueJson.isNotEmpty) {
        final decoded = jsonDecode(queueJson);
        if (decoded is List) {
          for (final item in decoded) {
            addJob(VideoProcessingJob.fromJson(
              Map<String, dynamic>.from(item as Map? ?? const {}),
            ));
          }
        } else if (decoded is Map) {
          addJob(VideoProcessingJob.fromJson(
            Map<String, dynamic>.from(decoded),
          ));
        }
      }
    } catch (_) {
      // Corrupt queue data should not block legacy migration or new jobs.
    }

    try {
      if (legacyJobJson != null && legacyJobJson.isNotEmpty) {
        final decoded = jsonDecode(legacyJobJson);
        if (decoded is Map) {
          addJob(VideoProcessingJob.fromJson(
            Map<String, dynamic>.from(decoded),
          ));
        }
      }
    } catch (_) {
      // Ignore corrupt legacy data.
    }

    return jobs;
  }

  static String encode(List<VideoProcessingJob> jobs) {
    return jsonEncode(jobs.map((job) => job.toJson()).toList());
  }

  static List<VideoProcessingJob> withoutJob(
    List<VideoProcessingJob> jobs,
    String jobId,
  ) {
    return jobs.where((job) => job.id != jobId).toList(growable: false);
  }

  static List<VideoProcessingJob> replaceOrAppend(
    List<VideoProcessingJob> jobs,
    VideoProcessingJob updatedJob,
  ) {
    var replaced = false;
    final updated = jobs.map((job) {
      if (job.id != updatedJob.id) return job;
      replaced = true;
      return updatedJob;
    }).toList();

    if (!replaced) updated.add(updatedJob);
    return updated;
  }

  static List<VideoProcessingJob> moveToEnd(
    List<VideoProcessingJob> jobs,
    VideoProcessingJob updatedJob,
  ) {
    return [
      ...withoutJob(jobs, updatedJob.id),
      updatedJob,
    ];
  }
}

class VideoProcessingJobRecovery {
  const VideoProcessingJobRecovery._();

  static bool hasUnmarkedInterruptedAttempt(VideoProcessingJob job) {
    final lastAttemptAtMs = job.lastAttemptAtMs;
    if (lastAttemptAtMs == null || job.lastError != null) return false;

    final lastInterruptedAtMs = job.lastInterruptedAtMs;
    return lastInterruptedAtMs == null || lastInterruptedAtMs < lastAttemptAtMs;
  }

  static List<VideoProcessingJob> markInterruptedJobs(
    List<VideoProcessingJob> jobs, {
    required int nowMs,
  }) {
    return jobs
        .map((job) => hasUnmarkedInterruptedAttempt(job)
            ? job.copyWith(
                interruptionCount: job.interruptionCount + 1,
                lastInterruptedAtMs: nowMs,
              )
            : job)
        .toList(growable: false);
  }

  static int countUnmarkedInterruptedAttempts(List<VideoProcessingJob> jobs) {
    return jobs.where(hasUnmarkedInterruptedAttempt).length;
  }
}

class VideoProcessingJobStorage {
  static const String pendingDirectoryName = 'pending_video_jobs';

  const VideoProcessingJobStorage._();

  static Future<Directory> pendingRootDirectory({
    Directory? rootDirectory,
  }) async {
    if (rootDirectory != null) {
      if (!await rootDirectory.exists()) {
        await rootDirectory.create(recursive: true);
      }
      return rootDirectory;
    }

    final docDir = await getApplicationDocumentsDirectory();
    final root = Directory(
      p.join(docDir.path, 'surveycam', pendingDirectoryName),
    );
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  static Future<VideoProcessingJob> stageSegments(
    VideoProcessingJob job, {
    Directory? rootDirectory,
  }) async {
    final root = await pendingRootDirectory(rootDirectory: rootDirectory);
    final jobDir = Directory(p.join(root.path, _safeJobId(job.id)));
    if (!await jobDir.exists()) {
      await jobDir.create(recursive: true);
    }

    try {
      final stagedSegments = <VideoProcessingSegment>[];
      for (var i = 0; i < job.segments.length; i++) {
        final segment = job.segments[i];
        final source = File(segment.path);
        if (!await source.exists()) {
          throw Exception('Video segment was not found: ${segment.path}');
        }

        final extension = p.extension(segment.path).isEmpty
            ? '.mp4'
            : p.extension(segment.path);
        final destination = File(
          p.join(
              jobDir.path, 'segment_${i.toString().padLeft(3, '0')}$extension'),
        );

        final stagedPath = await _moveOrCopySegment(source, destination);
        stagedSegments.add(segment.copyWith(path: stagedPath));
      }

      return job.copyWith(
        segments: stagedSegments,
        attemptCount: 0,
        lastAttemptAtMs: null,
        lastError: null,
        interruptionCount: 0,
        lastInterruptedAtMs: null,
      );
    } catch (_) {
      await _deleteQuietly(jobDir);
      rethrow;
    }
  }

  static Future<void> cleanupJob(
    VideoProcessingJob job, {
    Directory? rootDirectory,
  }) async {
    final root = await pendingRootDirectory(rootDirectory: rootDirectory);
    await _deleteQuietly(Directory(p.join(root.path, _safeJobId(job.id))));
  }

  static Future<String> _moveOrCopySegment(
    File source,
    File destination,
  ) async {
    final sourcePath = p.normalize(source.absolute.path);
    final destinationPath = p.normalize(destination.absolute.path);

    if (sourcePath == destinationPath) {
      return destination.path;
    }

    if (await destination.exists()) {
      await destination.delete();
    }

    try {
      final moved = await source.rename(destination.path);
      return moved.path;
    } catch (_) {
      final copied = await source.copy(destination.path);
      return copied.path;
    }
  }

  static String _safeJobId(String jobId) {
    final safe = jobId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return safe.isEmpty ? 'video_job' : safe;
  }

  static Future<void> _deleteQuietly(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {}
  }
}

class VideoProcessingFallback {
  static List<String> rawSavePaths({
    required List<VideoProcessingSegment> segments,
    String? mergedPath,
  }) {
    if (mergedPath != null && mergedPath.isNotEmpty) {
      return [mergedPath];
    }

    return segments
        .map((segment) => segment.path)
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
  }
}
