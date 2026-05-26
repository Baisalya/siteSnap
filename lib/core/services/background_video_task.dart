import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:surveycam/core/services/video_processing_job.dart';
import 'package:surveycam/core/utils/gallery_saver.dart';
import 'package:surveycam/core/utils/thumbnail_utils.dart';
import 'package:surveycam/features/camera/domain/camera_lens_type.dart';
import 'package:surveycam/features/overlay/presentation/video_watermark_processor.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(VideoProcessingTaskHandler());
}

class VideoProcessingTaskHandler extends TaskHandler {
  static const String pendingJobKey = 'pending_video_processing_job';
  static const String lastFailureKey = 'last_video_processing_failure';
  static const String cancelRequestedKey = 'cancel_video_processing_requested';

  static bool _isProcessing = false;
  static String? _lastFailedJobId;

  static Future<bool> hasPendingJob() async {
    final jobJson = await FlutterForegroundTask.getData<String>(
      key: pendingJobKey,
    );
    return jobJson != null && jobJson.isNotEmpty;
  }

  static Future<void> enqueueJob(VideoProcessingJob job) async {
    await FlutterForegroundTask.removeData(key: lastFailureKey);
    await FlutterForegroundTask.removeData(key: cancelRequestedKey);
    await FlutterForegroundTask.saveData(
      key: pendingJobKey,
      value: jsonEncode(job.toJson()),
    );
    _lastFailedJobId = null;
  }

  static Future<void> cancelProcessing() async {
    await FlutterForegroundTask.saveData(
      key: cancelRequestedKey,
      value: 'true',
    );
    await FlutterForegroundTask.removeData(key: pendingJobKey);
    await FlutterForegroundTask.removeData(key: lastFailureKey);
    await VideoWatermarkProcessor.cancelActiveProcessing();
    await FlutterForegroundTask.updateService(
      notificationTitle: 'SurveyCam - Video processing',
      notificationText: 'Video processing cancelled',
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

  @override
  void onStart(DateTime timestamp, SendPort? sendPort) {
    unawaited(_processPendingJob(sendPort));
  }

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {
    unawaited(_processPendingJob(sendPort));
  }

  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) {
    // Service destroyed
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  Future<void> _processPendingJob(SendPort? sendPort) async {
    if (_isProcessing) return;

    VideoProcessingJob? job;
    try {
      await _throwIfCancelRequested(sendPort);
      final jobJson = await FlutterForegroundTask.getData<String>(
        key: pendingJobKey,
      );
      if (jobJson == null || jobJson.isEmpty) {
        await FlutterForegroundTask.stopService();
        return;
      }

      job = VideoProcessingJob.fromJson(
        Map<String, dynamic>.from(jsonDecode(jobJson) as Map),
      );
      if (job.segments.isEmpty) {
        await FlutterForegroundTask.removeData(key: pendingJobKey);
        await FlutterForegroundTask.stopService();
        return;
      }
      if (_lastFailedJobId == job.id) {
        _send(sendPort, {
          'type': 'error',
          'error': 'Previous video processing attempt failed.',
        });
        await FlutterForegroundTask.stopService();
        return;
      }

      _isProcessing = true;
      await _progress(
        sendPort,
        0.05,
        'Preparing video watermark... 5%',
      );
      await _throwIfCancelRequested(sendPort);

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
            ),
          )
          .toList(growable: false);
      if (job.segments.length > 1 || needsMirror) {
        await _progress(sendPort, 0.10, 'Merging video segments... 10%');
        mergedPath = await VideoWatermarkProcessor.mergeVideos(
          job.segments.map((segment) => segment.path).toList(),
          mirrorMap: job.segments.map((segment) => segment.mirror).toList(),
          frontCameraPortraitCorrectionMap: frontCameraPortraitCorrectionMap,
        );
        await _throwIfCancelRequested(sendPort);
        if (mergedPath != null) {
          sourcePath = mergedPath;
        } else {
          canProcessOverlay = false;
        }
      }

      String? processedPath;
      if (canProcessOverlay && sourcePath != null) {
        await _progress(sendPort, 0.15, 'Generating watermark frames... 15%');
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
            _send(sendPort, {
              'type': 'progress',
              'value': progress,
              'message':
                  'Generating watermark frames... ${(progress * 100).toInt()}%',
            });
          },
        );
        await _throwIfCancelRequested(sendPort);

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
              _send(sendPort, {
                'type': 'progress',
                'value': progress,
                'message': message,
              });
              unawaited(_updateNotification(message));
            },
          );
          await _throwIfCancelRequested(sendPort);
        }
      }

      await _progress(sendPort, 0.95, 'Saving to gallery... 95%');
      await _throwIfCancelRequested(sendPort);

      final List<String> savedPaths = [];
      var savedWithoutOverlay = false;

      if (processedPath != null) {
        final savedPath = await GallerySaver.saveVideo(processedPath);
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
          sendPort,
          0.95,
          'Saving original video without overlay...',
        );
        for (final rawPath in rawPaths) {
          final savedPath = await GallerySaver.saveVideo(rawPath);
          await ThumbnailUtils.generateVideoThumbnail(savedPath);
          savedPaths.add(savedPath);
        }
      }

      await FlutterForegroundTask.removeData(key: pendingJobKey);
      await FlutterForegroundTask.removeData(key: cancelRequestedKey);
      await _updateNotification(savedWithoutOverlay
          ? 'Video saved without overlay'
          : 'Video saved successfully!');
      _send(sendPort, {
        'type': 'complete',
        'path': savedPaths.isEmpty ? null : savedPaths.first,
        'paths': savedPaths,
        'warning': savedWithoutOverlay ? 'Saved without overlay' : null,
      });

      unawaited(Future.delayed(const Duration(seconds: 2), () {
        FlutterForegroundTask.stopService();
      }));
    } on _VideoProcessingCancelledException {
      await FlutterForegroundTask.removeData(key: pendingJobKey);
      await FlutterForegroundTask.removeData(key: cancelRequestedKey);
      _send(sendPort, {
        'type': 'cancelled',
        'message': 'Video processing cancelled.',
      });
      await _updateNotification('Video processing cancelled');
      unawaited(Future.delayed(const Duration(seconds: 1), () {
        FlutterForegroundTask.stopService();
      }));
    } catch (e, stackTrace) {
      debugPrint('Background video processing error: $e\n$stackTrace');
      _lastFailedJobId = job?.id;
      await FlutterForegroundTask.removeData(key: pendingJobKey);
      await FlutterForegroundTask.saveData(
        key: lastFailureKey,
        value: e.toString(),
      );
      _send(sendPort, {
        'type': 'error',
        'error': e.toString(),
      });
      await _updateNotification('Video processing failed. Tap to reopen.');
      unawaited(Future.delayed(const Duration(seconds: 8), () {
        FlutterForegroundTask.stopService();
      }));
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _updateNotification(String text) {
    return FlutterForegroundTask.updateService(
      notificationTitle: 'SurveyCam - Video processing',
      notificationText: text,
    );
  }

  Future<void> _progress(SendPort? sendPort, double value, String message) {
    _send(sendPort, {
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

  Future<void> _throwIfCancelRequested(SendPort? sendPort) async {
    if (await _isCancelRequested()) {
      _send(sendPort, {
        'type': 'cancelled',
        'message': 'Video processing cancelled.',
      });
      throw const _VideoProcessingCancelledException();
    }
  }

  void _send(SendPort? sendPort, Map<String, dynamic> message) {
    sendPort?.send(message);
  }
}

class _VideoProcessingCancelledException implements Exception {
  const _VideoProcessingCancelledException();
}
