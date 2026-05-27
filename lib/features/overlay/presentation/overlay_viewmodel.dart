import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:surveycam/core/permissions/permission_service.dart';
import 'package:surveycam/core/services/background_video_task.dart';
import 'package:surveycam/core/services/image_processing_job.dart';
import 'package:surveycam/core/utils/gallery_saver.dart';
import 'package:surveycam/features/gallery/data/sitesnap_gallery_repository.dart';
import 'package:surveycam/features/gallery/presentation/last_image_provider.dart';

import 'package:surveycam/features/overlay/domain/overlay_model.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';
import 'package:surveycam/features/overlay/presentation/overlay_painter.dart';
import 'package:surveycam/features/overlay/presentation/overlay_settings_provider.dart';

import '../../camera/data/CameraState.dart';

final overlayViewModelProvider =
    StateNotifierProvider<OverlayViewModel, void>((ref) {
  return OverlayViewModel(ref);
});

class OverlayViewModel extends StateNotifier<void> {
  final Ref ref;

  OverlayViewModel(this.ref) : super(null);

  Future<Uint8List> processImage(
    File original,
    DeviceOrientation orientation, {
    required OverlayData overlayData,
    bool showOverlay = true,
    bool showWatermark = true,
    CameraAspectRatio? aspectRatio,
    bool mirror = false,
    OverlaySettings? settingsOverride,
  }) async {
    try {
      final OverlaySettings settings =
          settingsOverride ?? ref.read(overlaySettingsProvider);

      final bytes = await WatermarkProcessor.drawOverlay(
        original,
        overlayData,
        orientation,
        showOverlay: showOverlay,
        showWatermark: showWatermark,
        aspectRatio: aspectRatio,
        mirror: mirror,
        settings: settings,
      );

      return bytes;
    } catch (e) {
      debugPrint("processImage error: $e");
      return await original.readAsBytes();
    }
  }

  Future<File?> saveCapturedImage({
    required File original,
    required DeviceOrientation orientation,
    required OverlayData overlayData,
    bool showOverlay = true,
    bool showWatermark = true,
    CameraAspectRatio? aspectRatio,
    bool mirror = false,
  }) async {
    try {
      ref.read(lastImageProvider.notifier).state = original;
      ref.read(galleryFilesProvider.notifier).showFileImmediately(original);
      ref.read(galleryProcessingProvider.notifier).start(original);

      final settings = ref.read(overlaySettingsProvider);
      final now = DateTime.now();
      await VideoProcessingTaskHandler.enqueueImageJob(
        ImageProcessingJob(
          id: 'image_${now.microsecondsSinceEpoch}',
          originalPath: original.path,
          overlayData: overlayData,
          orientation: orientation,
          settings: settings,
          showOverlay: showOverlay,
          showWatermark: showWatermark,
          aspectRatio: aspectRatio,
          mirror: mirror,
          createdAtMs: now.millisecondsSinceEpoch,
        ),
      );
      await _startForegroundImageService();

      return null;
    } catch (e) {
      debugPrint("Background Save Failed: $e");
      ref.read(galleryProcessingProvider.notifier).fail(original);
      return null;
    }
  }

  Future<File?> saveCapturedImageInApp({
    required File original,
    required DeviceOrientation orientation,
    required OverlayData overlayData,
    bool showOverlay = true,
    bool showWatermark = true,
    CameraAspectRatio? aspectRatio,
    bool mirror = false,
  }) async {
    try {
      final bytes = await processImage(
        original,
        orientation,
        overlayData: overlayData,
        showOverlay: showOverlay,
        showWatermark: showWatermark,
        aspectRatio: aspectRatio,
        mirror: mirror,
      );

      final savedFile = await GallerySaver.saveImageBytes(bytes);
      ref.read(lastImageProvider.notifier).state = savedFile;
      ref
          .read(galleryProcessingProvider.notifier)
          .complete(original, savedFile);
      ref
          .read(galleryFilesProvider.notifier)
          .showFileImmediately(savedFile, replace: original);
      debugPrint("Background Save Complete");
      return savedFile;
    } catch (e) {
      debugPrint("In-app Save Failed: $e");
      ref.read(galleryProcessingProvider.notifier).fail(original);
      return null;
    }
  }

  Future<File?> savePreparedCapturedImage({
    required File original,
    required Future<Uint8List> preparedBytes,
  }) async {
    try {
      ref.read(lastImageProvider.notifier).state = original;
      ref.read(galleryFilesProvider.notifier).showFileImmediately(original);
      ref.read(galleryProcessingProvider.notifier).start(original);

      final bytes = await preparedBytes;
      if (bytes.isEmpty) {
        throw Exception('Prepared image was empty');
      }

      final savedFile = await GallerySaver.saveImageBytes(bytes);
      ref.read(lastImageProvider.notifier).state = savedFile;
      ref
          .read(galleryProcessingProvider.notifier)
          .complete(original, savedFile);
      ref
          .read(galleryFilesProvider.notifier)
          .showFileImmediately(savedFile, replace: original);
      debugPrint("Prepared Save Complete");
      return savedFile;
    } catch (e) {
      debugPrint("Prepared Save Failed: $e");
      ref.read(galleryProcessingProvider.notifier).fail(original);
      return null;
    }
  }

  Future<void> _startForegroundImageService() async {
    await PermissionService.requestNotificationPermission();

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'processing_channel',
        channelName: 'Media Processing',
        channelDescription: 'Shows progress of media processing',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'SurveyCam - Photo saving',
        notificationText: 'Preparing photo save...',
        callback: startCallback,
      );
    } else {
      await FlutterForegroundTask.startService(
        notificationTitle: 'SurveyCam - Photo saving',
        notificationText: 'Preparing photo save...',
        callback: startCallback,
      );
    }
  }
}
