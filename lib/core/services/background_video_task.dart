import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:surveycam/core/services/video_processing_job.dart';
import 'package:surveycam/core/utils/gallery_saver.dart';
import 'package:surveycam/core/utils/thumbnail_utils.dart';
import 'package:surveycam/features/overlay/presentation/video_watermark_processor.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(VideoProcessingTaskHandler());
}

class VideoProcessingTaskHandler extends TaskHandler {
  static const String pendingJobKey = 'pending_video_processing_job';

  static bool _isProcessing = false;
  static String? _lastFailedJobId;

  static Future<bool> hasPendingJob() async {
    final jobJson = await FlutterForegroundTask.getData<String>(
      key: pendingJobKey,
    );
    return jobJson != null && jobJson.isNotEmpty;
  }

  static Future<void> enqueueJob(VideoProcessingJob job) async {
    await FlutterForegroundTask.saveData(
      key: pendingJobKey,
      value: jsonEncode(job.toJson()),
    );
    _lastFailedJobId = null;
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
      final jobJson = await FlutterForegroundTask.getData<String>(
        key: pendingJobKey,
      );
      if (jobJson == null || jobJson.isEmpty) return;

      job = VideoProcessingJob.fromJson(
        Map<String, dynamic>.from(jsonDecode(jobJson) as Map),
      );
      if (job.segments.isEmpty) {
        await FlutterForegroundTask.removeData(key: pendingJobKey);
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
      _send(sendPort, {'type': 'progress', 'value': 0.05});
      await _updateNotification('Preparing video watermark... 5%');

      String? sourcePath =
          job.segments.length == 1 ? job.segments.single.path : null;
      String? mergedPath;
      var canProcessOverlay = job.history.isNotEmpty;
      final needsMirror = job.segments.any((segment) => segment.mirror);
      if (job.segments.length > 1 || needsMirror) {
        await _updateNotification('Merging video segments... 10%');
        mergedPath = await VideoWatermarkProcessor.mergeVideos(
          job.segments.map((segment) => segment.path).toList(),
          mirrorMap: job.segments.map((segment) => segment.mirror).toList(),
        );
        if (mergedPath != null) {
          sourcePath = mergedPath;
        } else {
          canProcessOverlay = false;
        }
      }

      String? processedPath;
      if (canProcessOverlay && sourcePath != null) {
        await _updateNotification('Generating watermark frames... 15%');
        final videoSize = await VideoWatermarkProcessor.getVideoDimensions(
          sourcePath,
        );
        final sequenceDir =
            await VideoWatermarkProcessor.generateVideoOverlaySequence(
          samples: job.history,
          width: videoSize.width.toDouble(),
          height: videoSize.height.toDouble(),
          onProgress: (p) {
            final progress = 0.15 + (p * 0.25);
            _send(sendPort, {'type': 'progress', 'value': progress});
          },
        );

        if (sequenceDir != null) {
          processedPath =
              await VideoWatermarkProcessor.applyOverlaySequenceToVideo(
            videoPath: sourcePath,
            sequenceDir: sequenceDir,
            frameCount: job.history.length,
            durationMs: job.durationMs,
            onProgress: (p) {
              final progress = 0.4 + (p * 0.5);
              _send(sendPort, {'type': 'progress', 'value': progress});
              unawaited(_updateNotification(
                  'Applying watermark... ${(progress * 100).toInt()}%'));
            },
          );
        }
      }

      _send(sendPort, {'type': 'progress', 'value': 0.95});
      await _updateNotification('Saving to gallery... 95%');

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

        await _updateNotification('Saving original video without overlay...');
        for (final rawPath in rawPaths) {
          final savedPath = await GallerySaver.saveVideo(rawPath);
          await ThumbnailUtils.generateVideoThumbnail(savedPath);
          savedPaths.add(savedPath);
        }
      }

      await FlutterForegroundTask.removeData(key: pendingJobKey);
      await _updateNotification(savedWithoutOverlay
          ? 'Video saved without overlay'
          : 'Video saved successfully!');
      _send(sendPort, {
        'type': 'complete',
        'path': savedPaths.isEmpty ? null : savedPaths.first,
        'paths': savedPaths,
        'warning': savedWithoutOverlay ? 'Saved without overlay' : null,
      });

      unawaited(Future.delayed(const Duration(seconds: 3), () {
        FlutterForegroundTask.stopService();
      }));
    } catch (e, stackTrace) {
      debugPrint('Background video processing error: $e\n$stackTrace');
      _lastFailedJobId = job?.id;
      _send(sendPort, {
        'type': 'error',
        'error': e.toString(),
      });
      await _updateNotification('Video processing failed');
      unawaited(Future.delayed(const Duration(seconds: 3), () {
        FlutterForegroundTask.stopService();
      }));
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _updateNotification(String text) {
    return FlutterForegroundTask.updateService(
      notificationTitle: 'SurveyCam - Processing',
      notificationText: text,
    );
  }

  void _send(SendPort? sendPort, Map<String, dynamic> message) {
    sendPort?.send(message);
  }
}
