# SiteSnap / SurveyCam Phase 7 — Production Hardening & Release Certification

## What Phase 7 changes

Phase 7 does not add another recording feature. It hardens the Phase 3–6
realtime CameraX pipeline so the app can make conservative production decisions
without reintroducing the old full-video overlay encode on the normal path.

### 1. Realtime overlay verification is generation-aware

The native CameraX bridge now tracks:

- overlay generation pushed by Flutter;
- last generation actually rendered by CameraX;
- frames rendered since enable;
- native error state;
- last frame/render timing;
- active overlay bitmap dimensions.

Flutter records two separate facts for every segment:

- `realtimeOverlayApplied`: CameraX definitely rendered realtime overlay frames.
- `realtimeOverlayHealthy`: the newest pushed generation rendered and strict
  health verification passed.

This distinction is important. A degraded realtime segment is **not** sent
through legacy overlay burn-in again, which would double the watermark. It is
also **not** allowed through the instant-save gate.

### 2. Long-recording memory/backpressure hardening

- Flutter realtime PNG updates remain coalesced.
- Raster pushes have a 120 ms minimum interval so rapid GPS/sensor/provider
  bursts cannot create an unbounded PNG queue.
- Consecutive bridge update failures are tracked for strict final verification.
- Identical legacy overlay snapshots are stored as sparse change-points instead
  of retaining identical 2-FPS history for long recordings.
- The legacy sequence generator already carries the latest sample forward until
  the next timestamp, so sparse unchanged history preserves visual behavior.
- Native overlay PNG payloads larger than 8 MiB are rejected before decode.
- Replaced native bitmaps are still recycled behind the CameraX effect handler
  to avoid recycling while a frame is drawing.

### 3. Low-storage preflight

On Android, recording startup queries usable app-volume storage through `StatFs`.

- At least 200 MiB must be available when the value can be read.
- If storage reporting is unavailable, the guard is non-blocking.
- This prevents a known class of zero-byte/truncated recordings caused by
  starting CameraX with critically low storage.

### 4. Finalized-file production gate

Before direct save or background finalization, every CameraX segment must:

- have a non-empty path;
- exist;
- contain at least one byte.

Only a single segment with verified realtime overlay health and no pending
mirror transform can use instant save. Everything else is routed through safe
background finalization.

Background output is checked again before Gallery save, and stream-copy concat
must produce a non-empty file before it is accepted.

### 5. Backward compatibility

`realtimeOverlayHealthy` is optional in persisted queue JSON. Older jobs that
only contain `realtimeOverlayApplied` inherit that value as their health default,
so pending Phase 3–6 jobs remain readable.

### 6. Local diagnostics

If a realtime segment contains overlay but fails strict health verification,
background finalization writes a local `realtime_overlay_health_degraded`
diagnostic. The overlay is not burned a second time.

## Required development-machine gate

Run from the project root:

```powershell
dart format lib test tool
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test test/recording_session_coordinator_test.dart test/realtime_video_overlay_bridge_test.dart test/recording_storage_guard_test.dart test/video_recording_production_gate_test.dart test/video_fast_finalization_test.dart test/video_processing_realtime_overlay_test.dart test/video_recording_backend_test.dart test/video_watermark_processor_test.dart
flutter test
flutter build apk --debug
```

Or run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\phase7_release_gate.ps1
```

## Device certification matrix

Use at least one Android 13+ physical device and the normal production camera
settings. The Motorola Edge 60 Stylus is a useful primary regression device.

1. Back camera portrait, 60 seconds, no rotation: stop must direct-save when
   native realtime health passes.
2. Back camera portrait -> landscapeLeft -> portrait during one recording:
   overlay position and text orientation must remain WYSIWYG.
3. landscapeLeft -> landscapeRight while recording: no mirrored/reversed overlay.
4. Front camera mirror OFF: preview and saved video must agree.
5. Front camera mirror ON: CameraX capture-time mirroring must agree with preview;
   no post-record `hflip` should run on the supported path.
6. Back -> front -> back persistent switch: one MP4 on supported CameraX path.
7. Toggle front mirror while actively recording: deliberate segment boundary;
   compatible output may use stream-copy concat.
8. 4:3 recording and 16:9 recording: overlay anchors must match visible preview.
9. 10-minute recording with GPS/time updates: no growing UI lag, no duplicate
   overlay, stable audio sync.
10. 30-minute recording: check thermal behavior, memory stability, audio sync,
    stop latency, and final file playback.
11. Background the app while recording: recording must finalize safely before
    camera disposal; foreground recovery must not expose a disposed controller.
12. Lock/unlock screen during recording and verify safe lifecycle finalization.
13. Start with less than 200 MiB free: recording must be refused before CameraX
    starts instead of producing a doomed file.
14. Force realtime bridge unavailable: legacy post-processing must still save a
    usable video.
15. Force/observe realtime health degradation: no duplicate overlay burn-in;
    job should use conservative background finalization.
16. Camera-switch segments with matching stream signatures: stream-copy concat.
17. Mismatched rotation/codec/audio signature: safe re-encode fallback.
18. Kill the app/background processing process during a fallback job, reopen,
    and verify pending-job recovery.

## Release acceptance criteria

Release candidate is accepted only when:

- `flutter analyze` has zero errors;
- full `flutter test` passes;
- Android debug build succeeds;
- all normal single-segment realtime recordings avoid post-overlay encode;
- front mirror and all four device orientations match preview;
- no duplicate overlay appears in fallback/finalization paths;
- persistent lens switching does not corrupt audio/video;
- fast concat is used only for definitive compatible stream signatures;
- low-storage guard works;
- 30-minute recording has no material memory growth or A/V drift;
- lifecycle interruption never loses the finalized source file.

The execution environment used to prepare Phase 7 does not include Flutter or
Dart, so SDK/device-dependent gates above must be executed on the development
machine before a Play Store production release.
