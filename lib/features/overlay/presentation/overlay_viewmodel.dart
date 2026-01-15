import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/exif_utils.dart';
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

  /// Takes original camera image
  /// Applies SAME overlay as live preview
  /// Returns processed image file (watermark baked in)
  Future<File> processImage(File original) async {
    // 1️⃣ Get the SAME overlay data used in live preview
    final overlay = ref.read(overlayPreviewProvider);

    // 2️⃣ Draw watermark on the image
    final processed = await drawOverlay(original, overlay);

    // ❌ NOTHING ELSE HERE
    // ❌ NO ExifUtils
    // ❌ NO copying bytes

    return processed;
  }
}
