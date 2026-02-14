import 'dart:io';
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
      DeviceOrientation orientation,
      ) async {

    /// ✅ 1️⃣ READ ORIGINAL IMAGE
    final bytes = await original.readAsBytes();

    img.Image? image = img.decodeImage(bytes);
    if (image == null) return original;

    /// ✅ 2️⃣ BAKE EXIF ORIENTATION INTO PIXELS
    /// Camera saves rotation in EXIF.
    /// When we re-encode image, EXIF is lost.
    /// So we must apply rotation permanently here.
    image = img.bakeOrientation(image);

    /// ✅ 3️⃣ WRITE TEMP ORIENTED IMAGE
    final orientedFile = await original.writeAsBytes(
      img.encodeJpg(image, quality: 100),
    );

    /// ✅ 4️⃣ GET SAME OVERLAY DATA AS LIVE PREVIEW
    final overlayData = ref.read(overlayPreviewProvider);

    /// ✅ 5️⃣ DRAW OVERLAY USING SAME ORIENTATION
    final processedFile = await drawOverlay(
      orientedFile,
      overlayData,
      orientation,
    );

    return processedFile;
  }
}
