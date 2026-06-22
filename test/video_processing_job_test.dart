import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:surveycam/core/services/video_processing_job.dart';
import 'package:surveycam/features/camera/domain/camera_lens_type.dart';

VideoProcessingJob _job(
  String id, {
  List<VideoProcessingSegment> segments = const [],
  int attemptCount = 0,
  int? lastAttemptAtMs,
  String? lastError,
}) {
  return VideoProcessingJob(
    id: id,
    segments: segments,
    history: const [],
    durationMs: 1200,
    createdAtMs: 42,
    attemptCount: attemptCount,
    lastAttemptAtMs: lastAttemptAtMs,
    lastError: lastError,
  );
}

void main() {
  test('video queue decodes current queue and legacy single pending job', () {
    final queued = [
      _job('first'),
      _job('second'),
    ];
    final legacy = _job('legacy');

    final decoded = VideoProcessingJobQueue.decode(
      VideoProcessingJobQueue.encode(queued),
      legacyJobJson: jsonEncode(legacy.toJson()),
    );

    expect(decoded.map((job) => job.id), ['first', 'second', 'legacy']);
  });

  test('video queue keeps failed job metadata while moving it to the end', () {
    final first = _job('first');
    final second = _job('second');
    final failed = first.copyWith(
      attemptCount: 1,
      lastAttemptAtMs: 123,
      lastError: 'encoder failed',
    );

    final queue = VideoProcessingJobQueue.moveToEnd(
      [first, second],
      failed,
    );

    expect(queue.map((job) => job.id), ['second', 'first']);
    expect(queue.last.attemptCount, 1);
    expect(queue.last.lastAttemptAtMs, 123);
    expect(queue.last.lastError, 'encoder failed');
  });

  test('video queue preserves interruption recovery metadata', () {
    final queued = [
      _job(
        'interrupted',
        lastAttemptAtMs: 200,
      ).copyWith(
        interruptionCount: 1,
        lastInterruptedAtMs: 250,
      ),
    ];

    final decoded = VideoProcessingJobQueue.decode(
      VideoProcessingJobQueue.encode(queued),
    );

    expect(decoded.single.interruptionCount, 1);
    expect(decoded.single.lastInterruptedAtMs, 250);
  });

  test('video recovery marks only jobs interrupted during an active attempt',
      () {
    final waiting = _job('waiting');
    final failed = _job(
      'failed',
      lastAttemptAtMs: 100,
      lastError: 'encoder failed',
    );
    final alreadyMarked = _job('already_marked', lastAttemptAtMs: 200).copyWith(
      interruptionCount: 1,
      lastInterruptedAtMs: 250,
    );
    final interrupted = _job('interrupted', lastAttemptAtMs: 300);

    final recovered = VideoProcessingJobRecovery.markInterruptedJobs(
      [waiting, failed, alreadyMarked, interrupted],
      nowMs: 400,
    );

    expect(recovered[0].interruptionCount, 0);
    expect(recovered[1].interruptionCount, 0);
    expect(recovered[2].interruptionCount, 1);
    expect(recovered[2].lastInterruptedAtMs, 250);
    expect(recovered[3].interruptionCount, 1);
    expect(recovered[3].lastInterruptedAtMs, 400);
  });

  test('video recovery can mark the next attempt after a prior interruption',
      () {
    final job = _job('retry', lastAttemptAtMs: 500).copyWith(
      interruptionCount: 1,
      lastInterruptedAtMs: 250,
    );

    expect(VideoProcessingJobRecovery.hasUnmarkedInterruptedAttempt(job), true);

    final recovered = VideoProcessingJobRecovery.markInterruptedJobs(
      [job],
      nowMs: 600,
    ).single;

    expect(recovered.interruptionCount, 2);
    expect(recovered.lastInterruptedAtMs, 600);
  });

  test('video segment staging moves recordings into durable job storage',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'surveycam_video_job_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final source = File(p.join(tempDir.path, 'camera_tmp.mp4'));
    await source.writeAsString('raw video');
    final pendingRoot = Directory(p.join(tempDir.path, 'pending'));
    final job = _job(
      'video:1',
      segments: [
        VideoProcessingSegment(
          path: source.path,
          lens: CameraLensType.normal,
        ),
      ],
      attemptCount: 2,
      lastAttemptAtMs: 88,
      lastError: 'old failure',
    ).copyWith(
      interruptionCount: 3,
      lastInterruptedAtMs: 99,
    );

    final staged = await VideoProcessingJobStorage.stageSegments(
      job,
      rootDirectory: pendingRoot,
    );

    final stagedFile = File(staged.segments.single.path);
    expect(await stagedFile.exists(), isTrue);
    expect(await stagedFile.readAsString(), 'raw video');
    expect(p.basename(p.dirname(stagedFile.path)), 'video_1');
    expect(p.basename(stagedFile.path), 'segment_000.mp4');
    expect(staged.attemptCount, 0);
    expect(staged.lastAttemptAtMs, isNull);
    expect(staged.lastError, isNull);
    expect(staged.interruptionCount, 0);
    expect(staged.lastInterruptedAtMs, isNull);

    await VideoProcessingJobStorage.cleanupJob(
      staged,
      rootDirectory: pendingRoot,
    );

    expect(
        await Directory(p.join(pendingRoot.path, 'video_1')).exists(), isFalse);
  });
}
