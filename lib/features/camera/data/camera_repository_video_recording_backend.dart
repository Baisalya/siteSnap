import 'package:flutter/services.dart';
import 'package:surveycam/features/camera/data/realtime_video_overlay_bridge.dart';
import 'package:surveycam/features/camera/domain/camera_lens_type.dart';
import 'package:surveycam/features/camera/domain/realtime_overlay_segment_report.dart';
import 'package:surveycam/features/camera/domain/camera_repository.dart';
import 'package:surveycam/features/camera/domain/video_recording_backend.dart';
import 'package:surveycam/features/overlay/domain/overlay_render_snapshot.dart';

class CameraRepositoryVideoRecordingBackend implements VideoRecordingBackend {
  final CameraRepository repository;
  final RealtimeVideoOverlayBridge realtimeOverlayBridge;

  CameraRepositoryVideoRecordingBackend(
    this.repository, {
    RealtimeVideoOverlayBridge? realtimeOverlayBridge,
  }) : realtimeOverlayBridge =
            realtimeOverlayBridge ?? RealtimeVideoOverlayBridge();

  @override
  Future<void> start() => repository.startVideoRecording();

  @override
  Future<String> stop() async {
    final file = await repository.stopVideoRecording();
    return file.path;
  }

  @override
  Future<bool> configureFrontVideoMirroring(bool enabled) =>
      realtimeOverlayBridge.configureFrontVideoMirroring(enabled);

  @override
  Future<bool> requiresFrontVideoMirrorRebuild(bool enabled) =>
      realtimeOverlayBridge.requiresFrontVideoMirrorRebuild(enabled);

  @override
  Future<bool> switchLensWhileRecording(CameraLensType lens) =>
      repository.switchLensWhileRecording(lens);

  @override
  Future<bool> armRealtimeOverlay() => realtimeOverlayBridge.arm();

  @override
  Future<bool> prepareRealtimeOverlay(
    OverlayRenderSnapshot snapshot, {
    double? viewportAspectRatio,
    DeviceOrientation? captureOrientation,
  }) =>
      realtimeOverlayBridge.prepare(
        snapshot,
        viewportAspectRatio: viewportAspectRatio,
        captureOrientation: captureOrientation,
      );

  @override
  Future<bool> activateRealtimeOverlay() => realtimeOverlayBridge.activate();

  @override
  void updateRealtimeOverlay(
    OverlayRenderSnapshot snapshot, {
    double? viewportAspectRatio,
  }) {
    realtimeOverlayBridge.update(
      snapshot,
      viewportAspectRatio: viewportAspectRatio,
    );
  }

  @override
  void updateRealtimeOrientation(DeviceOrientation orientation) {
    realtimeOverlayBridge.updateOrientation(orientation);
  }

  @override
  Future<void> freezeRealtimeOverlayUpdatesForStop() =>
      realtimeOverlayBridge.freezeUpdatesForStop();

  @override
  Future<RealtimeOverlaySegmentReport> inspectRealtimeOverlaySegment() =>
      realtimeOverlayBridge.inspectCurrentSegment();

  @override
  Future<bool> confirmRealtimeOverlayApplied() =>
      realtimeOverlayBridge.confirmCurrentSegmentApplied();

  @override
  Future<void> finishRealtimeOverlay() => realtimeOverlayBridge.finish();

  @override
  bool get isRealtimeOverlayActive => realtimeOverlayBridge.isActive;
}
