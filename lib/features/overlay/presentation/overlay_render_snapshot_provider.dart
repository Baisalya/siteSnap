import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:surveycam/core/utils/device_orientation_provider.dart';
import 'package:surveycam/features/overlay/domain/overlay_render_snapshot.dart';
import 'package:surveycam/features/overlay/presentation/overlay_preview_state.dart';
import 'package:surveycam/features/overlay/presentation/overlay_settings_provider.dart';

/// One provider for the exact visual state painted on the camera preview and
/// sampled by video recording sessions.
final overlayRenderSnapshotProvider = Provider<OverlayRenderSnapshot>((ref) {
  return OverlayRenderSnapshot(
    data: ref.watch(overlayPreviewProvider),
    settings: ref.watch(effectiveOverlaySettingsProvider),
    orientation: ref.watch(deviceOrientationProvider),
  );
});
