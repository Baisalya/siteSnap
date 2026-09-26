import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/features/camera/application/recording_session_coordinator.dart';
import 'package:surveycam/features/camera/domain/camera_lens_type.dart';
import 'package:surveycam/features/camera/domain/video_recording_session.dart';
import 'package:surveycam/features/overlay/domain/overlay_model.dart';
import 'package:surveycam/features/overlay/domain/overlay_render_snapshot.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';

OverlayRenderSnapshot _snapshot({
  String note = '',
  DeviceOrientation orientation = DeviceOrientation.portraitUp,
}) {
  return OverlayRenderSnapshot(
    data: OverlayData(
      dateTime: '2026-09-09 18:30:00',
      latitude: 20.0,
      longitude: 85.0,
      altitude: 10.0,
      heading: 90.0,
      direction: 'E',
      note: note,
    ),
    settings: const OverlaySettings(),
    orientation: orientation,
  );
}

void main() {
  test(
      'background during lens switch saves finalized segment without duplication',
      () {
    final coordinator = RecordingSessionCoordinator();
    coordinator.begin(initialSnapshot: _snapshot(), projectId: 'project-a');
    coordinator.addSegment(const VideoRecordingSegment(
      path: 'finished-before-switch.mp4',
      lens: CameraLensType.normal,
      realtimeOverlayApplied: true,
    ));
    final completed = coordinator.complete(finalSnapshot: _snapshot());
    expect(completed.segments, hasLength(1));
    expect(completed.segments.single.path, 'finished-before-switch.mp4');
    expect(completed.projectId, 'project-a');
    expect(coordinator.isActive, isFalse);
  });

  test('empty recording cannot be treated as a successful save', () {
    final coordinator = RecordingSessionCoordinator();
    coordinator.begin(initialSnapshot: _snapshot(), projectId: null);
    expect(() => coordinator.complete(finalSnapshot: _snapshot()),
        throwsStateError);
  });
  test('recording session owns duration, segments and overlay history', () {
    var now = DateTime(2026, 9, 9, 18, 30);
    final coordinator = RecordingSessionCoordinator(now: () => now);

    coordinator.begin(
      initialSnapshot: _snapshot(note: 'Start'),
      projectId: 'project-a',
    );

    now = now.add(const Duration(milliseconds: 500));
    coordinator.recordOverlay(_snapshot(note: 'Middle'), force: true);
    coordinator.addSegment(
      const VideoRecordingSegment(
        path: 'segment-1.mp4',
        lens: CameraLensType.normal,
      ),
    );

    coordinator.markCurrentSegmentCameraSwitch();
    expect(coordinator.takeCurrentSegmentCameraSwitchMarker(), isTrue);
    expect(coordinator.takeCurrentSegmentCameraSwitchMarker(), isFalse);
    coordinator.markCurrentSegmentCameraSwitch();

    now = now.add(const Duration(milliseconds: 750));
    final completed = coordinator.complete(
      finalSegment: VideoRecordingSegment(
        path: 'segment-2.mp4',
        lens: CameraLensType.front,
        mirror: true,
        realtimeOverlayApplied: true,
        containsCameraSwitches:
            coordinator.takeCurrentSegmentCameraSwitchMarker(),
      ),
      finalSnapshot: _snapshot(
        note: 'End',
        orientation: DeviceOrientation.landscapeLeft,
      ),
    );

    expect(completed.durationMs, 1250);
    expect(completed.projectId, 'project-a');
    expect(completed.segments.map((segment) => segment.path), [
      'segment-1.mp4',
      'segment-2.mp4',
    ]);
    expect(completed.segments.last.mirror, isTrue);
    expect(completed.segments.last.realtimeOverlayApplied, isTrue);
    expect(completed.segments.last.containsCameraSwitches, isTrue);
    expect(completed.overlayHistory.first.timestampMs, 0);
    expect(completed.overlayHistory.last.timestampMs, 1250);
    expect(
      completed.overlayHistory.last.orientation,
      DeviceOrientation.landscapeLeft,
    );
    expect(coordinator.isActive, isFalse);
  });

  test('unchanged overlay snapshots stay sparse during long recordings', () {
    var now = DateTime(2026, 9, 9, 18, 30);
    final coordinator = RecordingSessionCoordinator(now: () => now);
    final snapshot = _snapshot(note: 'Same');

    coordinator.begin(initialSnapshot: snapshot, projectId: null);
    now = now.add(const Duration(milliseconds: 40));
    coordinator.recordOverlay(snapshot);

    expect(coordinator.overlayHistory, hasLength(1));

    now = now.add(const Duration(seconds: 10));
    coordinator.recordOverlay(snapshot);
    expect(coordinator.overlayHistory, hasLength(1));

    coordinator.recordOverlay(snapshot, force: true);
    expect(coordinator.overlayHistory, hasLength(2));
  });

  test('abort clears active session state', () {
    final coordinator = RecordingSessionCoordinator();
    coordinator.begin(
      initialSnapshot: _snapshot(),
      projectId: 'project-a',
    );
    coordinator.addSegment(
      const VideoRecordingSegment(
        path: 'segment.mp4',
        lens: CameraLensType.normal,
      ),
    );

    coordinator.abort();

    expect(coordinator.isActive, isFalse);
    expect(coordinator.segments, isEmpty);
    expect(coordinator.overlayHistory, isEmpty);
  });
}
