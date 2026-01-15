import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/utils/exif_utils.dart';
import '../domain/overlay_model.dart';
import 'overlay_painter.dart';

final overlayViewModelProvider =
StateNotifierProvider<OverlayViewModel, void>((ref) {
  return OverlayViewModel(ref);
});

class OverlayViewModel extends StateNotifier<void> {
  final Ref ref;

  OverlayViewModel(this.ref) : super(null);

  /// Returns processed image file
  Future<File> processImage(
      File original,
      String dateTime,
      ) async {
    // ✅ REQUEST PERMISSIONS FIRST
    await PermissionService.requestCameraAndLocation();

    final position =
    await ref.read(locationRepositoryProvider).getLocation();

    final overlay = OverlayData(
      dateTime: dateTime,
      lat: position.latitude,
      lng: position.longitude,
      altitude: position.altitude,
      direction: 'N',
      note: 'Sample Note',
    );

    final processed = await drawOverlay(original, overlay);

    await ExifUtils.preserveExif(
      source: original,
      destination: processed,
    );

    return processed;
  }

}
