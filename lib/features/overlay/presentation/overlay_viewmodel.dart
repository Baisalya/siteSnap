import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../camera/data/CameraState.dart';
import '../../../core/utils/gallery_saver.dart';

import '../domain/overlay_model.dart';
import 'overlay_painter.dart';

final overlayViewModelProvider =
StateNotifierProvider<OverlayViewModel, void>((ref) {
  return OverlayViewModel(ref);
});

class OverlayViewModel extends StateNotifier<void> {
  final Ref ref;

  OverlayViewModel(this.ref) : super(null);

  /// =======================================================
  /// PROCESS IMAGE (OPTIMIZED FOR SPEED)
  /// =======================================================
  Future<Uint8List> processImage(
      File original,
      DeviceOrientation orientation, {
        required OverlayData overlayData,
        bool showOverlay = true,
        bool showWatermark = true,
        ui.Image? decodedImage,
        CameraAspectRatio? aspectRatio,
        bool mirror = false,
      }) async {
    try {
      // 🚀 DIRECT PASS: Skip the slow 'image' library decode/bake.
      // drawOverlay uses ui.Canvas (Hardware Accelerated) which is much faster.
      final bytes = await drawOverlay(
        original,
        overlayData,
        orientation,
        showOverlay: showOverlay,
        showWatermark: showWatermark,
        decodedImage: decodedImage,
        aspectRatio: aspectRatio,
        mirror: mirror,
      );

      return bytes;
    } catch (e) {
      debugPrint("processImage error: $e");
      return await original.readAsBytes();
    }
  }

  /// =======================================================
  /// SAVE IN BACKGROUND (NON-BLOCKING)
  /// =======================================================
  Future<void> saveCapturedImage({
    required File original,
    required DeviceOrientation orientation,
    required OverlayData overlayData,
    bool showOverlay = true,
    bool showWatermark = true,
    ui.Image? decodedImage,
    CameraAspectRatio? aspectRatio,
    bool mirror = false,
  }) async {
    try {
      // Run the slow processing in the background
      final bytes = await processImage(
        original,
        orientation,
        overlayData: overlayData,
        showOverlay: showOverlay,
        showWatermark: showWatermark,
        decodedImage: decodedImage,
        aspectRatio: aspectRatio,
        mirror: mirror,
      );

      await GallerySaver.saveImageBytes(bytes);
      debugPrint("✅ Background Save Complete");
    } catch (e) {
      debugPrint("❌ Background Save Failed: $e");
    }
  }
}
