import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/features/camera/domain/camera_lens_type.dart';
import 'package:surveycam/features/camera/domain/video_recording_production_gate.dart';
import 'package:surveycam/features/camera/domain/video_recording_session.dart';

CompletedVideoRecordingSession _session(VideoRecordingSegment segment) {
  return CompletedVideoRecordingSession(
    segments: <VideoRecordingSegment>[segment],
    overlayHistory: const [],
    durationMs: 1000,
    projectId: null,
  );
}

void main() {
  test('verified realtime file is eligible for instant save', () async {
    final dir = await Directory.systemTemp.createTemp('surveycam_gate_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/video.mp4');
    await file.writeAsBytes(<int>[0, 1, 2, 3]);

    final decision = await VideoRecordingProductionGate.evaluate(
      _session(VideoRecordingSegment(
        path: file.path,
        lens: CameraLensType.normal,
        realtimeOverlayApplied: true,
        realtimeOverlayHealthy: true,
      )),
    );

    expect(decision.route, VideoFinalizationRoute.instantSave);
  });

  test('applied but degraded realtime overlay finalizes without reburn',
      () async {
    final dir = await Directory.systemTemp.createTemp('surveycam_gate_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/video.mp4');
    await file.writeAsBytes(<int>[0, 1, 2, 3]);

    final decision = await VideoRecordingProductionGate.evaluate(
      _session(VideoRecordingSegment(
        path: file.path,
        lens: CameraLensType.normal,
        realtimeOverlayApplied: true,
        realtimeOverlayHealthy: false,
      )),
    );

    expect(decision.route, VideoFinalizationRoute.backgroundFinalize);
  });

  test('missing or empty finalized file is rejected', () async {
    final dir = await Directory.systemTemp.createTemp('surveycam_gate_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/empty.mp4');
    await file.create();

    final decision = await VideoRecordingProductionGate.evaluate(
      _session(VideoRecordingSegment(
        path: file.path,
        lens: CameraLensType.normal,
        realtimeOverlayApplied: true,
        realtimeOverlayHealthy: true,
      )),
    );

    expect(decision.route, VideoFinalizationRoute.reject);
  });
}
