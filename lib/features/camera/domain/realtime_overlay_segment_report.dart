/// Production-grade verification result for one native recording segment.
///
/// [applied] means CameraX rendered at least one overlay generation into the
/// encoded stream. [healthy] is intentionally stricter and is used by the
/// instant-save gate: the newest pushed generation must have rendered and no
/// native/Dart bridge error may have remained unresolved.
class RealtimeOverlaySegmentReport {
  final bool applied;
  final bool healthy;
  final int renderedFrames;
  final int overlayGeneration;
  final int renderedOverlayGeneration;
  final int updateFailureCount;
  final String? reason;

  const RealtimeOverlaySegmentReport({
    required this.applied,
    required this.healthy,
    this.renderedFrames = 0,
    this.overlayGeneration = 0,
    this.renderedOverlayGeneration = 0,
    this.updateFailureCount = 0,
    this.reason,
  });

  const RealtimeOverlaySegmentReport.unavailable({String? reason})
      : this(
          applied: false,
          healthy: false,
          reason: reason ?? 'realtime_overlay_unavailable',
        );
}
