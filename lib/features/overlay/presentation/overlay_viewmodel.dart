import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:surveycam/core/permissions/permission_service.dart';
import 'package:surveycam/core/services/background_video_task.dart';
import 'package:surveycam/core/services/image_processing_job.dart';
import 'package:surveycam/core/services/media_audit_service.dart';
import 'package:surveycam/core/utils/gallery_saver.dart';
import 'package:surveycam/features/gallery/data/sitesnap_gallery_repository.dart';
import 'package:surveycam/features/gallery/presentation/last_image_provider.dart';
import 'package:surveycam/features/projects/presentation/project_provider.dart';

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
      await ref
          .read(projectProvider.notifier)
          .assignFileToActiveProject(original);

      final settings = ref.read(overlaySettingsProvider);
      final projectId = ref.read(projectProvider).activeProjectId;
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
          projectId: projectId,
        ),
      );
      await _startForegroundImageService();

      return null;
    } catch (e) {
      debugPrint("Background Save Failed: $e");
      await MediaAuditService.recordFailure(
        event: 'image_background_save_enqueue_failed',
        error: e,
        details: {'originalPath': original.path},
      );
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
      final settings = ref.read(overlaySettingsProvider);
      await ref
          .read(projectProvider.notifier)
          .assignFileToActiveProject(savedFile, replace: original);
      await MediaAuditService.recordImageSave(
        originalFile: original,
        outputFile: savedFile,
        overlayData: overlayData.toJson(),
        overlaySettings: settings.toJson(),
        orientation: orientation.name,
        showOverlay: showOverlay,
        showWatermark: showWatermark,
        mirror: mirror,
      );
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
      await MediaAuditService.recordFailure(
        event: 'image_in_app_save_failed',
        error: e,
        details: {'originalPath': original.path},
      );
      ref.read(galleryProcessingProvider.notifier).fail(original);
      return null;
    }
  }

  Future<File?> savePreparedCapturedImage({
    required File original,
    required Future<Uint8List> preparedBytes,
    required OverlayData overlayData,
    required OverlaySettings settings,
    required DeviceOrientation orientation,
    required bool showOverlay,
    required bool showWatermark,
    required bool mirror,
    bool showRawPlaceholder = true,
  }) async {
    try {
      var rawPlaceholderShown = false;

      // 🔥 OPTIMIZATION: Try to wait for the prepared bytes for a very short window (150ms).
      // If they are ready, we skip showing the "original" (no-overlay) image in the gallery
      // entirely, avoiding the "flash" of a raw photo before the watermarked one appears.
      Future<File> saveFinalBytes(Uint8List bytes) async {
        if (bytes.isEmpty) throw Exception('Prepared image was empty');

        final savedFile = await GallerySaver.saveImageBytes(bytes);
        await ref
            .read(projectProvider.notifier)
            .assignFileToActiveProject(savedFile, replace: original);
        await MediaAuditService.recordImageSave(
          originalFile: original,
          outputFile: savedFile,
          overlayData: overlayData.toJson(),
          overlaySettings: settings.toJson(),
          orientation: orientation.name,
          showOverlay: showOverlay,
          showWatermark: showWatermark,
          mirror: mirror,
        );
        ref.read(lastImageProvider.notifier).state = savedFile;
        if (rawPlaceholderShown) {
          ref
              .read(galleryProcessingProvider.notifier)
              .complete(original, savedFile);
        }
        ref
            .read(galleryFilesProvider.notifier)
            .showFileImmediately(savedFile, replace: original);
        return savedFile;
      }

      Uint8List? bytes;
      if (showRawPlaceholder) {
        try {
          bytes =
              await preparedBytes.timeout(const Duration(milliseconds: 150));
        } catch (_) {
          // Not ready yet, proceed with showing the original as a placeholder.
        }
      } else {
        bytes = await preparedBytes;
      }

      if (bytes != null) {
        return await saveFinalBytes(bytes);
      }

      // If we are here, processing is taking longer. Show original with a processing indicator.
      ref.read(lastImageProvider.notifier).state = original;
      ref.read(galleryFilesProvider.notifier).showFileImmediately(original);
      ref.read(galleryProcessingProvider.notifier).start(original);
      rawPlaceholderShown = true;
      await ref
          .read(projectProvider.notifier)
          .assignFileToActiveProject(original);

      final finalBytes = await preparedBytes;
      if (finalBytes.isEmpty) {
        throw Exception('Prepared image was empty');
      }

      return await saveFinalBytes(finalBytes);
    } catch (e) {
      debugPrint("Prepared Save Failed: $e");
      await MediaAuditService.recordFailure(
        event: 'image_prepared_save_failed',
        error: e,
        details: {'originalPath': original.path},
      );
      if (showRawPlaceholder) {
        ref.read(galleryProcessingProvider.notifier).fail(original);
      }
      return null;
    }
  }

  Future<void> _startForegroundImageService() async {
    await PermissionService.requestNotificationPermission();

    // 1. Core initialization is now in main.dart

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
