import 'dart:async';

import 'package:surveycam/features/camera/domain/video_recording_session.dart';
import 'package:surveycam/features/overlay/domain/overlay_render_snapshot.dart';
import 'package:surveycam/features/overlay/domain/video_overlay_sample.dart';

/// Owns all mutable state that belongs to one logical video recording.
///
/// CameraViewModel remains responsible for UI/camera commands. This class owns
/// session duration, overlay sampling, segment aggregation and project binding,
/// which gives the future realtime recorder one stable integration boundary.
class RecordingSessionCoordinator {
  final DateTime Function() _now;
  final Duration sampleInterval;

  final List<VideoRecordingSegment> _segments = <VideoRecordingSegment>[];
  final List<VideoOverlaySample> _overlayHistory = <VideoOverlaySample>[];

  DateTime? _startedAt;
  String? _projectId;
  Timer? _sampleTimer;
  bool _currentSegmentContainsCameraSwitches = false;

  RecordingSessionCoordinator({
    DateTime Function()? now,
    this.sampleInterval = const Duration(milliseconds: 500),
  }) : _now = now ?? DateTime.now;

  bool get isActive => _startedAt != null;
  List<VideoRecordingSegment> get segments =>
      List<VideoRecordingSegment>.unmodifiable(_segments);
  List<VideoOverlaySample> get overlayHistory =>
      List<VideoOverlaySample>.unmodifiable(_overlayHistory);

  void begin({
    required OverlayRenderSnapshot initialSnapshot,
    required String? projectId,
    bool clearSegments = true,
  }) {
    stopSampling();
    if (clearSegments) {
      _segments.clear();
    }
    _overlayHistory.clear();
    _projectId = projectId;
    _startedAt = _now();
    _currentSegmentContainsCameraSwitches = false;
    recordOverlay(initialSnapshot, force: true);
  }

  void startSampling({
    required OverlayRenderSnapshot Function() snapshotReader,
    required bool Function() shouldContinue,
  }) {
    stopSampling();
    if (!isActive) return;

    _sampleTimer = Timer.periodic(sampleInterval, (timer) {
      if (!isActive || !shouldContinue()) {
        timer.cancel();
        if (identical(_sampleTimer, timer)) {
          _sampleTimer = null;
        }
        return;
      }
      recordOverlay(snapshotReader());
    });
  }

  void stopSampling() {
    _sampleTimer?.cancel();
    _sampleTimer = null;
  }

  void recordOverlay(
    OverlayRenderSnapshot snapshot, {
    bool force = false,
  }) {
    final startedAt = _startedAt;
    if (startedAt == null) return;

    final timestampMs =
        _now().difference(startedAt).inMilliseconds.clamp(0, 1 << 31).toInt();

    if (!force && _overlayHistory.isNotEmpty) {
      final previous = _overlayHistory.last;
      // Sparse change-points are enough for the legacy frame generator: it
      // carries the latest sample forward until the next timestamp. Avoid
      // retaining identical 2-FPS snapshots for long recordings.
      if (previous.snapshot == snapshot) return;
    }

    _overlayHistory.add(
      VideoOverlaySample.fromSnapshot(
        snapshot,
        timestampMs: timestampMs,
      ),
    );
  }

  /// Marks that the currently open native file changed cameras without
  /// stopping its persistent Recorder.
  void markCurrentSegmentCameraSwitch() {
    if (!isActive) return;
    _currentSegmentContainsCameraSwitches = true;
  }

  /// Returns and resets the current-file switch marker when a native segment
  /// is finalized.
  bool takeCurrentSegmentCameraSwitchMarker() {
    final value = _currentSegmentContainsCameraSwitches;
    _currentSegmentContainsCameraSwitches = false;
    return value;
  }

  void addSegment(VideoRecordingSegment segment) {
    if (!isActive) return;
    _segments.add(segment);
  }

  CompletedVideoRecordingSession complete({
    required VideoRecordingSegment finalSegment,
    required OverlayRenderSnapshot finalSnapshot,
  }) {
    final startedAt = _startedAt;
    if (startedAt == null) {
      throw StateError('No active video recording session to complete.');
    }

    stopSampling();
    addSegment(finalSegment);
    recordOverlay(finalSnapshot, force: true);

    final history = List<VideoOverlaySample>.from(_overlayHistory);
    if (history.isEmpty) {
      history.add(
        VideoOverlaySample.fromSnapshot(finalSnapshot, timestampMs: 0),
      );
    }

    final result = CompletedVideoRecordingSession(
      segments: List<VideoRecordingSegment>.unmodifiable(_segments),
      overlayHistory: List<VideoOverlaySample>.unmodifiable(history),
      durationMs:
          _now().difference(startedAt).inMilliseconds.clamp(0, 1 << 31).toInt(),
      projectId: _projectId,
    );

    _reset(clearSegments: true);
    return result;
  }

  void abort({bool clearSegments = true}) {
    stopSampling();
    _reset(clearSegments: clearSegments);
  }

  void _reset({required bool clearSegments}) {
    if (clearSegments) {
      _segments.clear();
    }
    _overlayHistory.clear();
    _startedAt = null;
    _projectId = null;
    _currentSegmentContainsCameraSwitches = false;
  }
}
