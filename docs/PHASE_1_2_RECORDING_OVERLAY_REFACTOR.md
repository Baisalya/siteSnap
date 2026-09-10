# Phase 1 + Phase 2 — Recording Boundary + Unified Overlay Layout

## What changed

### Recording architecture boundary
- `VideoRecordingBackend` is now the stable start/stop contract used by `CameraViewModel`.
- `CameraRepositoryVideoRecordingBackend` preserves the current Flutter `camera` implementation behind that contract.
- `RecordingSessionCoordinator` owns logical recording state: project binding, segment list, duration, overlay history, periodic sampling and cleanup.
- Recording-only segment/history state was removed from `CameraState`; it no longer leaks session internals into UI state.

This boundary is intentionally compatible with the current recorder. A later CameraX realtime-overlay backend can replace `VideoRecordingBackend` without moving session bookkeeping back into the ViewModel.

### Unified overlay render model
- `OverlayRenderSnapshot` groups the exact `OverlayData`, `OverlaySettings` and `DeviceOrientation` used for one visual state.
- `overlayRenderSnapshotProvider` supplies the same snapshot to camera preview and recording sampling.
- `OverlayFrameGeometry` owns orientation/frame normalization rules.
- `OverlayCardRenderer` owns the information-card typography, fields, padding, background and bottom-left/bottom-right placement.
- `LiveOverlayPainter` is now a thin adapter over `OverlayCardRenderer`.
- `VideoWatermarkProcessor` delegates its information-card rendering and frame orientation mapping to the same shared engine.
- `VideoOverlaySample` can be created from / converted back to an `OverlayRenderSnapshot` while retaining the existing JSON schema for pending video jobs.

## Behavior intentionally unchanged in this phase
- Video still records through the existing Flutter camera / CameraX plugin path.
- Video overlay burn-in still uses the legacy background FFmpeg processing path.
- Foreground processing/recovery remains available.
- Existing camera switch and front-video mirror segmentation remain supported.

The realtime CameraX compositor belongs to the next implementation phase; this phase creates the seam it will plug into.

## Verification added
- `test/recording_session_coordinator_test.dart`
- `test/overlay_render_snapshot_test.dart`
- `test/video_recording_backend_test.dart`
- `test/video_watermark_processor_test.dart` now includes live-vs-saved card-render parity coverage.

## Run on the project machine

```powershell
dart format lib test
flutter analyze
flutter test test/recording_session_coordinator_test.dart test/overlay_render_snapshot_test.dart test/video_recording_backend_test.dart test/live_overlay_painter_test.dart test/video_watermark_processor_test.dart
flutter test
```

## Environment note

The implementation workspace used to prepare this phase does not contain a Flutter/Dart SDK, so the commands above could not be executed there. Run them on the normal SiteSnap Flutter development machine before merging/releasing.
