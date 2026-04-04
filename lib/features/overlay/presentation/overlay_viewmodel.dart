import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../domain/overlay_model.dart';
import 'overlay_painter.dart';
import 'overlay_preview_state.dart';

final overlayViewModelProvider =
StateNotifierProvider<OverlayViewModel, void>((ref) {
  return OverlayViewModel(ref);
});

class OverlayViewModel extends StateNotifier<void> {
  final Ref ref;

  OverlayViewModel(this.ref) : super(null);

  /// =======================================================
  /// PROCESS IMAGE (FINAL STABLE VERSION)
  /// =======================================================
  Future<File> processImage(
      File original,
      DeviceOrientation orientation, {
        required OverlayData overlayData, // 🔥 ADD THIS
        bool showOverlay = true,
        bool showWatermark = true,
      }) async {
    try {
      /// ===============================
      /// 1️⃣ READ ORIGINAL
      /// ===============================
      final bytes = await original.readAsBytes();

      if (bytes.isEmpty) {
        return original; // safety
      }

      img.Image? image = img.decodeImage(bytes);

      /// ❌ If decode fails → fallback to original
      if (image == null) {
        return original;
      }

      /// ===============================
      /// 2️⃣ FIX ORIENTATION
      /// ===============================
      image = img.bakeOrientation(image);

      /// ===============================
      /// 3️⃣ CREATE SAFE TEMP FILE
      /// ===============================
      final orientedPath =
      original.path.replaceFirst('.jpg', '_oriented.jpg');

      final orientedBytes = img.encodeJpg(image, quality: 100);

      /// 🚨 CRITICAL CHECK
      if (orientedBytes.isEmpty) {
        return original;
      }

      final orientedFile =
      await File(orientedPath).writeAsBytes(orientedBytes);

      /// ===============================
      /// 4️⃣ OVERLAY DATA
      /// ===============================
/*
      final overlayData = ref.read(overlayPreviewProvider);
*/

      /// ===============================
      /// 5️⃣ DRAW OVERLAY SAFELY
      /// ===============================
      final processedFile = await drawOverlay(
        orientedFile,
        overlayData,
        orientation,
        showOverlay: showOverlay,
        showWatermark: showWatermark,
      );

      return processedFile;

    } catch (e) {
      debugPrint("processImage error: $e");

      /// ✅ NEVER CRASH UI
      return original;
    }
  }
}
