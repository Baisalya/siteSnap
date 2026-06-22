import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:surveycam/core/services/media_audit_service.dart';
import 'package:surveycam/core/services/image_processing_job.dart';
import 'package:surveycam/core/services/video_processing_job.dart';
import 'package:surveycam/core/utils/gallery_saver.dart';
import 'package:surveycam/core/utils/thumbnail_utils.dart';
import 'package:surveycam/features/camera/domain/camera_lens_type.dart';
import 'package:surveycam/features/overlay/presentation/overlay_painter.dart';
import 'package:surveycam/features/overlay/presentation/video_watermark_processor.dart';
import 'package:surveycam/features/projects/data/project_storage.dart';

@pragma('vm:entry-point')
void startCallback() {
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(VideoProcessingTaskHandler());
}

class VideoProcessingTaskHandler extends TaskHandler {
  // Legacy single-slot key kept so existing pending work can migrate.
  static const String pendingJobKey = 'pending_video_processing_job';
  static const String pendingJobQueueKey = 'pending_video_processing_jobs';
  static const String pendingImageJobKey = 'pending_image_processing_job';
  static const String lastFailureKey = 'last_video_processing_failure';
  static const String lastImageFailureKey = 'last_image_processing_failure';
  static const String cancelRequestedKey = 'cancel_video_processing_requested';

  static bool _isProcessing = false;
  static final Set<String> _failedJobIdsThisRun = <String>{};

  static Future<bool> hasPendingJob() async {
    return (await _loadVideoJobQueue()).isNotEmpty;
  }

  static Future<VideoProcessingRecoveryReport>
      preparePendingVideoJobsForRestart({
    required bool serviceWasRunning,
  }) async {
    final queue = await _loadVideoJobQueue();
    if (queue.isEmpty || serviceWasRunning) {
      return VideoProcessingRecoveryReport(
        pendingVideoJobCount: queue.length,
        interruptedVideoJobCount: 0,
      );
    }

    final interruptedCount =
        VideoProcessingJobRecovery.countUnmarkedInterruptedAttempts(queue);
    if (interruptedCount == 0) {
      return VideoProcessingRecoveryReport(
        pendingVideoJobCount: queue.length,
        interruptedVideoJobCount: 0,
      );
    }

    final recoveredQueue = VideoProcessingJobRecovery.markInterruptedJobs(
      queue,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _saveVideoJobQueue(recoveredQueue);
    return VideoProcessingRecoveryReport(
      pendingVideoJobCount: recoveredQueue.length,
      interruptedVideoJobCount: interruptedCount,
    );
  }

  static Future<bool> hasPendingImageJob() async {
    final jobJson = await FlutterForegroundTask.getData<String>(
      key: pendingImageJobKey,
    );
    return _decodeImageJobQueue(jobJson).isNotEmpty;
  }

  static Future<void> enqueueJob(VideoProcessingJob job) async {
    await FlutterForegroundTask.removeData(key: lastFailureKey);
    await FlutterForegroundTask.removeData(key: cancelRequestedKey);
    final stagedJob = await VideoProcessingJobStorage.stageSegments(job);
    final queue = await _loadVideoJobQueue();
    await _saveVideoJobQueue([
      ...VideoProcessingJobQueue.withoutJob(queue, stagedJob.id),
      stagedJob,
    ]);
    _failedJobIdsThisRun.remove(stagedJob.id);
  }

  static Future<void> enqueueImageJob(ImageProcessingJob job) async {
    await FlutterForegroundTask.removeData(key: lastImageFailureKey);
    final existingJobJson = await FlutterForegroundTask.getData<String>(
      key: pendingImageJobKey,
    );
    final queue = _decodeImageJobQueue(existingJobJson)..add(job.toJson());
    await FlutterForegroundTask.saveData(
      key: pendingImageJobKey,
      value: jsonEncode(queue),
    );
  }

  static List<Map<String, dynamic>> _decodeImageJobQueue(String? jobJson) {
    if (jobJson == null || jobJson.isEmpty) return [];
    try {
      final decoded = jsonDecode(jobJson);
      if (decoded is List) {
        return decoded
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }
      if (decoded is Map) {
        return [Map<String, dynamic>.from(decoded)];
      }
    } catch (_) {
      return [];
    }
    return [];
  }

  static Future<void> cancelProcessing() async {
    final queuedJobs = await _loadVideoJobQueue();
    await Future.wait(
      queuedJobs.map(VideoProcessingJobStorage.cleanupJob),
    );
    await FlutterForegroundTask.saveData(
      key: cancelRequestedKey,
      value: 'true',
    );
    await FlutterForegroundTask.removeData(key: pendingJobKey);
    await FlutterForegroundTask.removeData(key: pendingJobQueueKey);
    await FlutterForegroundTask.removeData(key: pendingImageJobKey);
    await FlutterForegroundTask.removeData(key: lastFailureKey);
    await FlutterForegroundTask.removeData(key: lastImageFailureKey);
    _failedJobIdsThisRun.clear();
    await VideoWatermarkProcessor.cancelActiveProcessing();
    await FlutterForegroundTask.updateService(
      notificationTitle: 'SurveyCam - Media processing',
      notificationText: 'Processing cancelled',
    );
    unawaited(Future.delayed(const Duration(seconds: 1), () {
      FlutterForegroundTask.stopService();
    }));
  }

  static Future<String?> takeLastFailure() async {
    final failure = await FlutterForegroundTask.getData<String>(
      key: lastFailureKey,
    );
    if (failure != null && failure.isNotEmpty) {
      await FlutterForegroundTask.removeData(key: lastFailureKey);
      return failure;
    }
    return null;
  }

  static Future<String?> takeLastImageFailure() async {
    final failure = await FlutterForegroundTask.getData<String>(
      key: lastImageFailureKey,
    );
    if (failure != null && failure.isNotEmpty) {
      await FlutterForegroundTask.removeData(key: lastImageFailureKey);
      return failure;
    }
    return null;
  }

  static Future<List<VideoProcessingJob>> _loadVideoJobQueue() async {
    final queueJson = await FlutterForegroundTask.getData<String>(
      key: pendingJobQueueKey,
    );
    final legacyJobJson = await FlutterForegroundTask.getData<String>(
      key: pendingJobKey,
    );
    final queue = VideoProcessingJobQueue.decode(
      queueJson,
      legacyJobJson: legacyJobJson,
    );

    if (legacyJobJson != null && legacyJobJson.isNotEmpty) {
      await _saveVideoJobQueue(queue);
      await FlutterForegroundTask.removeData(key: pendingJobKey);
    }

    return queue;
  }

  static Future<void> _saveVideoJobQueue(
    List<VideoProcessingJob> queue,
  ) async {
    await FlutterForegroundTask.removeData(key: pendingJobKey);
    if (queue.isEmpty) {
      await FlutterForegroundTask.removeData(key: pendingJobQueueKey);
      return;
    }

    await FlutterForegroundTask.saveData(
      key: pendingJobQueueKey,
      value: VideoProcessingJobQueue.encode(queue),
    );
  }

  static VideoProcessingJob? _nextRunnableVideoJob(
    List<VideoProcessingJob> queue,
  ) {
    for (final job in queue) {
      if (!_failedJobIdsThisRun.contains(job.id)) return job;
    }
    return null;
  }

  static Future<void> _completeVideoJob(VideoProcessingJob job) async {
    final queue = await _loadVideoJobQueue();
    await _saveVideoJobQueue(
      VideoProcessingJobQueue.withoutJob(queue, job.id),
    );
    _failedJobIdsThisRun.remove(job.id);
    await VideoProcessingJobStorage.cleanupJob(job);
  }

  static Future<void> _moveFailedVideoJobToQueueEnd(
    VideoProcessingJob failedJob,
  ) async {
    final queue = await _loadVideoJobQueue();
    await _saveVideoJobQueue(
      VideoProcessingJobQueue.moveToEnd(queue, failedJob),
    );
  }

  static Future<void> _replaceVideoJob(VideoProcessingJob updatedJob) async {
    final queue = await _loadVideoJobQueue();
    await _saveVideoJobQueue(
      VideoProcessingJobQueue.replaceOrAppend(queue, updatedJob),
    );
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _failedJobIdsThisRun.clear();
    unawaited(_processPendingJob());
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_processPendingJob());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    if (_isProcessing) {
      await MediaAuditService.recordFailure(
        event: 'video_processing_service_destroyed',
        error: 'Foreground service was destroyed while processing video',
        details: {
          'isTimeout': isTimeout,
          'timestampMs': timestamp.millisecondsSinceEpoch,
        },
      );
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  Future<void> _processPendingJob() async {
    if (_isProcessing) return;

    VideoProcessingJob? job;
    try {
      await _throwIfCancelRequested();
      final videoQueue = await _loadVideoJobQueue();
      job = _nextRunnableVideoJob(videoQueue);
      final imageJobJson = await FlutterForegroundTask.getData<String>(
        key: pendingImageJobKey,
      );
      if (job == null) {
        if (_decodeImageJobQueue(imageJobJson).isNotEmpty) {
          _isProcessing = true;
          await _processPendingImageJob(imageJobJson!);
          return;
        }
        await FlutterForegroundTask.stopService();
        return;
      }

      if (job.segments.isEmpty) {
        await _completeVideoJob(job);
        return;
      }

      _isProcessing = true;
      job = job.copyWith(
        lastAttemptAtMs: DateTime.now().millisecondsSinceEpoch,
        lastError: null,
      );
      await _replaceVideoJob(job);
      await _progress(
        0.05,
        'Preparing video watermark... 5%',
      );
      await _throwIfCancelRequested();

      String? sourcePath =
          job.segments.length == 1 ? job.segments.single.path : null;
      String? mergedPath;
      var canProcessOverlay = job.history.isNotEmpty;
      final needsMirror = job.segments.any((segment) => segment.mirror);
      final recordingOrientation =
          VideoWatermarkProcessor.preferredOrientationForSamples(job.history);
      final frontCameraPortraitCorrectionMap = job.segments
          .map(
            (segment) => VideoWatermarkProcessor
                .shouldApplyFrontCameraPortraitCorrection(
              lens: segment.lens,
              recordingOrientation: recordingOrientation,
              mirrored: segment.mirror,
            ),
          )
          .toList(growable: false);
      if (job.segments.length > 1 || needsMirror) {
        await _progress(0.10, 'Merging video segments... 10%');
        mergedPath = await VideoWatermarkProcessor.mergeVideos(
          job.segments.map((segment) => segment.path).toList(),
          mirrorMap: job.segments.map((segment) => segment.mirror).toList(),
          frontCameraPortraitCorrectionMap: frontCameraPortraitCorrectionMap,
        );
        await _throwIfCancelRequested();
        if (mergedPath != null) {
          sourcePath = mergedPath;
        } else {
          canProcessOverlay = false;
        }
      }

      String? processedPath;
      if (canProcessOverlay && sourcePath != null) {
        await _progress(0.15, 'Generating watermark frames... 15%');
        final videoSize = await VideoWatermarkProcessor.getVideoDimensions(
          sourcePath,
        );
        final sequenceDir =
            await VideoWatermarkProcessor.generateVideoOverlaySequence(
          samples: job.history,
          width: videoSize.width.toDouble(),
          height: videoSize.height.toDouble(),
          durationMs: job.durationMs,
          shouldCancel: _isCancelRequested,
          onProgress: (p) {
            final progress = 0.15 + (p * 0.25);
            _send({
              'type': 'progress',
              'value': progress,
              'message':
                  'Generating watermark frames... ${(progress * 100).toInt()}%',
            });
          },
        );
        await _throwIfCancelRequested();

        if (sequenceDir != null) {
          final correctRawFrontPortrait = mergedPath == null &&
              job.segments.length == 1 &&
              job.segments.single.lens == CameraLensType.front &&
              frontCameraPortraitCorrectionMap.single;
          processedPath =
              await VideoWatermarkProcessor.applyOverlaySequenceToVideo(
            videoPath: sourcePath,
            sequenceDir: sequenceDir,
            frameCount: job.history.length,
            durationMs: job.durationMs,
            correctFrontCameraPortrait: correctRawFrontPortrait,
            onProgress: (p) {
              final progress = 0.4 + (p * 0.5);
              final message =
                  'Applying watermark... ${(progress * 100).toInt()}%';
              _send({
                'type': 'progress',
                'value': progress,
                'message': message,
              });
              unawaited(_updateNotification(message));
            },
          );
          await _throwIfCancelRequested();
        }
      }

      await _progress(0.95, 'Saving to gallery... 95%');
      await _throwIfCancelRequested();

      final List<String> savedPaths = [];
      var savedWithoutOverlay = false;

      if (processedPath != null) {
        final savedPath = await GallerySaver.saveVideo(processedPath);
        await ProjectStorage().assignFilePath(
          filePath: savedPath,
          projectId: job.projectId,
        );
        await MediaAuditService.recordVideoSave(
          sourceFiles:
              job.segments.map((segment) => File(segment.path)).toList(),
          outputFile: File(savedPath),
          overlayHistory: job.history.map((sample) => sample.toJson()).toList(),
          durationMs: job.durationMs,
          jobId: job.id,
          savedWithoutOverlay: false,
        );
        await ThumbnailUtils.generateVideoThumbnail(savedPath);
        savedPaths.add(savedPath);
      } else {
        savedWithoutOverlay = true;
        final rawPaths = VideoProcessingFallback.rawSavePaths(
          segments: job.segments,
          mergedPath: mergedPath,
        );
        if (rawPaths.isEmpty) {
          throw Exception('No video file available to save');
        }

        await _progress(
          0.95,
          'Saving original video without overlay...',
        );
        for (final rawPath in rawPaths) {
          final savedPath = await GallerySaver.saveVideo(rawPath);
          await ProjectStorage().assignFilePath(
            filePath: savedPath,
            projectId: job.projectId,
          );
          await MediaAuditService.recordVideoSave(
            sourceFiles:
                job.segments.map((segment) => File(segment.path)).toList(),
            outputFile: File(savedPath),
            overlayHistory:
                job.history.map((sample) => sample.toJson()).toList(),
            durationMs: job.durationMs,
            jobId: job.id,
            savedWithoutOverlay: true,
          );
          await ThumbnailUtils.generateVideoThumbnail(savedPath);
          savedPaths.add(savedPath);
        }
      }

      await _completeVideoJob(job);
      await FlutterForegroundTask.removeData(key: cancelRequestedKey);
      await _updateNotification(savedWithoutOverlay
          ? 'Video saved without overlay'
          : 'Video saved successfully!');
      _send({
        'type': 'complete',
        'path': savedPaths.isEmpty ? null : savedPaths.first,
        'paths': savedPaths,
        'warning': savedWithoutOverlay ? 'Saved without overlay' : null,
      });

      unawaited(Future.delayed(const Duration(seconds: 2), () {
        _stopServiceIfIdle();
      }));
    } on _VideoProcessingCancelledException {
      if (job != null) {
        await _completeVideoJob(job);
      }
      await FlutterForegroundTask.removeData(key: cancelRequestedKey);
      _send({
        'type': 'cancelled',
        'message': 'Video processing cancelled.',
      });
      await _updateNotification('Video processing cancelled');
      unawaited(Future.delayed(const Duration(seconds: 1), () {
        _stopServiceIfIdle();
      }));
    } catch (e, stackTrace) {
      debugPrint('Background video processing error: $e\n$stackTrace');
      if (job != null) {
        final failedJob = job.copyWith(
          attemptCount: job.attemptCount + 1,
          lastAttemptAtMs: DateTime.now().millisecondsSinceEpoch,
          lastError: e.toString(),
        );
        _failedJobIdsThisRun.add(failedJob.id);
        await _moveFailedVideoJobToQueueEnd(failedJob);
        await MediaAuditService.recordFailure(
          event: 'video_processing_job_failed',
          error: e,
          details: {
            'jobId': failedJob.id,
            'attemptCount': failedJob.attemptCount,
            'interruptionCount': failedJob.interruptionCount,
          },
        );
      }
      await FlutterForegroundTask.saveData(
        key: lastFailureKey,
        value: e.toString(),
      );
      _send({
        'type': 'error',
        'error': e.toString(),
      });
      await _updateNotification('Video processing failed. Tap to reopen.');
      unawaited(Future.delayed(const Duration(seconds: 8), () {
        _stopServiceIfIdle();
      }));
    } finally {
      _isProcessing = false;
      if (await _hasRunnablePendingJob()) {
        unawaited(Future.microtask(() => _processPendingJob()));
      }
    }
  }

  Future<bool> _hasRunnablePendingJob() async {
    if (_nextRunnableVideoJob(await _loadVideoJobQueue()) != null) {
      return true;
    }

    final imageJobJson = await FlutterForegroundTask.getData<String>(
      key: pendingImageJobKey,
    );
    return _decodeImageJobQueue(imageJobJson).isNotEmpty;
  }

  Future<void> _stopServiceIfIdle() async {
    if (!await _hasRunnablePendingJob()) {
      await FlutterForegroundTask.stopService();
    }
  }

  Future<void> _processPendingImageJob(
    String jobJson,
  ) async {
    ImageProcessingJob? imageJob;
    try {
      final queue = _decodeImageJobQueue(jobJson);
      if (queue.isEmpty) {
        await FlutterForegroundTask.removeData(key: pendingImageJobKey);
        return;
      }
      imageJob = ImageProcessingJob.fromJson(queue.first);
      if (imageJob.originalPath.isEmpty) {
        await _removeImageJobFromQueue(imageJob.id);
        return;
      }

      final originalFile = File(imageJob.originalPath);
      if (!await originalFile.exists()) {
        throw Exception('Original photo file was not found');
      }

      await _imageProgress('Saving photo in background... 8%');
      final bytes = await WatermarkProcessor.drawOverlay(
        originalFile,
        imageJob.overlayData,
        imageJob.orientation,
        showOverlay: imageJob.showOverlay,
        showWatermark: imageJob.showWatermark,
        aspectRatio: imageJob.aspectRatio,
        mirror: imageJob.mirror,
        settings: imageJob.settings,
      );

      await _imageProgress('Finishing photo save... 88%');
      final savedFile = await GallerySaver.saveImageBytes(bytes);
      await ProjectStorage().assignFilePath(
        filePath: savedFile.path,
        projectId: imageJob.projectId,
        replacePath: imageJob.originalPath,
      );
      await MediaAuditService.recordImageSave(
        originalFile: originalFile,
        outputFile: savedFile,
        overlayData: imageJob.overlayData.toJson(),
        overlaySettings: imageJob.settings.toJson(),
        orientation: imageJob.orientation.name,
        showOverlay: imageJob.showOverlay,
        showWatermark: imageJob.showWatermark,
        mirror: imageJob.mirror,
        jobId: imageJob.id,
      );

      await _removeImageJobFromQueue(imageJob.id);
      await FlutterForegroundTask.removeData(key: lastImageFailureKey);
      await _updateNotification('Photo saved successfully!');
      _send({
        'type': 'image_complete',
        'originalPath': imageJob.originalPath,
        'path': savedFile.path,
      });

      unawaited(Future.delayed(const Duration(seconds: 2), () {
        _stopServiceIfIdle();
      }));
    } catch (e, stackTrace) {
      debugPrint('Background image processing error: $e\n$stackTrace');
      if (imageJob != null) {
        await _removeImageJobFromQueue(imageJob.id);
      } else {
        await FlutterForegroundTask.removeData(key: pendingImageJobKey);
      }
      await FlutterForegroundTask.saveData(
        key: lastImageFailureKey,
        value: e.toString(),
      );
      await _updateNotification('Photo save failed. Tap to reopen.');
      _send({
        'type': 'image_error',
        'originalPath': imageJob?.originalPath,
        'error': e.toString(),
      });
      unawaited(Future.delayed(const Duration(seconds: 8), () {
        _stopServiceIfIdle();
      }));
    }
  }

  Future<void> _removeImageJobFromQueue(String jobId) async {
    final jobJson = await FlutterForegroundTask.getData<String>(
      key: pendingImageJobKey,
    );
    final queue = _decodeImageJobQueue(jobJson)
        .where((job) => job['id'] != jobId)
        .toList();
    if (queue.isEmpty) {
      await FlutterForegroundTask.removeData(key: pendingImageJobKey);
    } else {
      await FlutterForegroundTask.saveData(
        key: pendingImageJobKey,
        value: jsonEncode(queue),
      );
    }
  }

  Future<void> _updateNotification(String text) {
    return FlutterForegroundTask.updateService(
      notificationTitle: 'SurveyCam - Media processing',
      notificationText: text,
    );
  }

  Future<void> _imageProgress(String message) {
    return _updateNotification(message);
  }

  Future<void> _progress(double value, String message) {
    _send({
      'type': 'progress',
      'value': value,
      'message': message,
    });
    return _updateNotification(message);
  }

  Future<bool> _isCancelRequested() async {
    final requested = await FlutterForegroundTask.getData<String>(
      key: cancelRequestedKey,
    );
    return requested == 'true';
  }

  Future<void> _throwIfCancelRequested() async {
    if (await _isCancelRequested()) {
      _send({
        'type': 'cancelled',
        'message': 'Video processing cancelled.',
      });
      throw const _VideoProcessingCancelledException();
    }
  }

  void _send(Map<String, dynamic> message) {
    FlutterForegroundTask.sendDataToMain(message);
  }
}

class _VideoProcessingCancelledException implements Exception {
  const _VideoProcessingCancelledException();
}

class VideoProcessingRecoveryReport {
  final int pendingVideoJobCount;
  final int interruptedVideoJobCount;

  const VideoProcessingRecoveryReport({
    required this.pendingVideoJobCount,
    required this.interruptedVideoJobCount,
  });

  bool get recoveredInterruptedVideo => interruptedVideoJobCount > 0;
}
