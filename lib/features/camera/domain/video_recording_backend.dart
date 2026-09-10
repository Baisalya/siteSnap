import 'package:flutter/services.dart';
import 'package:surveycam/features/camera/domain/camera_lens_type.dart';
import 'package:surveycam/features/camera/domain/realtime_overlay_segment_report.dart';
import 'package:surveycam/features/overlay/domain/overlay_render_snapshot.dart';

/// Stable recording boundary used by the camera presentation layer.
///
/// The default repository backend remains the actual recorder. On Android it
/// can additionally arm SiteSnap's CameraX recording compositor bridge. The
/// compositor preserves CameraX's camera transform and blends only the app HUD.
/// If that bridge is unavailable or cannot prepare a frame, callers keep using
/// the legacy post-processing pipeline.
abstract class VideoRecordingBackend {
  Future<void> start();

  /// Finalizes the active native recording and returns its temporary file path.
  Future<String> stop();

  /// Requests capture-time front-camera mirroring. A true result means the
  /// current VideoCapture accepted the native CameraX mirror policy, so no
  /// post-record hflip is required for that segment.
  Future<bool> configureFrontVideoMirroring(bool enabled) async => false;

  /// True only when the Android CameraX VideoCapture exists but was built with
  /// a different mirror mode and therefore must be recreated before recording.
  Future<bool> requiresFrontVideoMirrorRebuild(bool enabled) async => false;

  /// Attempts to change lenses while keeping the same persistent native
  /// recording/file alive. False asks the caller to use segmented fallback.
  Future<bool> switchLensWhileRecording(CameraLensType lens) async => false;

  /// Arms realtime CameraX effect injection before VideoCapture is bound.
  Future<bool> armRealtimeOverlay() async => false;

  /// Begins the realtime handshake before native recording starts. On Android
  /// this pre-binds VideoCapture, resolves real CameraX geometry, and prepares
  /// the first raster before Recorder.start().
  Future<bool> prepareRealtimeOverlay(
    OverlayRenderSnapshot snapshot, {
    double? viewportAspectRatio,
    DeviceOrientation? captureOrientation,
  }) async =>
      false;

  /// Completes the handshake after native recording starts by confirming that
  /// at least one newly recorded frame actually rendered the prepared raster.
  Future<bool> activateRealtimeOverlay() async => false;

  /// Schedules an updated raster while a realtime recording is active.
  void updateRealtimeOverlay(
    OverlayRenderSnapshot snapshot, {
    double? viewportAspectRatio,
  }) {}

  /// Compatibility hook for a physical orientation event. Production uses the
  /// full overlay snapshot so only the app-owned HUD moves; CameraX camera
  /// pixels and the running Recorder are never rotated/restarted here.
  void updateRealtimeOrientation(DeviceOrientation orientation) {}

  /// Freezes realtime HUD raster updates immediately before the native
  /// recorder is stopped. Native render status remains available for
  /// certification after finalization.
  Future<void> freezeRealtimeOverlayUpdatesForStop() async {}

  /// Returns production verification for the current CameraX segment.
  ///
  /// [RealtimeOverlaySegmentReport.applied] prevents duplicate legacy overlay
  /// burn-in. The stricter [RealtimeOverlaySegmentReport.healthy] is required
  /// before the segment can bypass background finalization entirely.
  Future<RealtimeOverlaySegmentReport> inspectRealtimeOverlaySegment() async =>
      RealtimeOverlaySegmentReport(
        applied: isRealtimeOverlayActive,
        healthy: isRealtimeOverlayActive,
      );

  /// Backward-compatible convenience for existing callers/tests.
  Future<bool> confirmRealtimeOverlayApplied() async =>
      (await inspectRealtimeOverlaySegment()).applied;

  /// Disables/clears the realtime raster after the recorder has finalized.
  Future<void> finishRealtimeOverlay() async {}

  bool get isRealtimeOverlayActive => false;
}
