# SiteSnap Phase 7.1 — CameraX Geometry Handshake + True Realtime Activation

## Root cause fixed

The device log showed `Realtime CameraX overlay: no VideoCapture frame geometry` before CameraX attached/configured the `VideoCapture` use case. Later in the same recording CameraX reported valid 1920x1080 transformation information, proving the old realtime preparation was querying geometry too early and falling back before VideoCapture existed.

Phase 7.1 changes the ordering from:

`prepare -> geometry(null) -> fallback -> bind VideoCapture -> record -> FFmpeg overlay`

to:

`arm -> pre-bind VideoCapture -> ResolutionInfo geometry -> first Flutter raster -> enable OverlayEffect -> start Recorder -> verify recorded overlay frame`

## Production behavior

For a supported normal Android recording:

1. Flutter arms the realtime bridge.
2. Native code pre-binds the existing CameraX `VideoCapture` without starting MP4 recording.
3. `VideoCapture.getResolutionInfo()` supplies the real selected crop/rotation geometry.
4. Flutter renders the existing shared `OverlayRenderSnapshot` into a transparent raster using that geometry.
5. Native `OverlayEffect` is enabled for `VIDEO_CAPTURE` only.
6. CameraX Recorder starts.
7. After `VideoRecordEventStart`, SiteSnap resets verification counters and confirms a newly recorded frame rendered the current overlay generation.
8. On stop, SiteSnap settles the latest raster while frames are still flowing and evaluates the strict production gate.
9. One healthy, transform-free segment is saved directly to Gallery. No legacy overlay sequence or FFmpeg overlay encode is created.

Flutter `CustomPaint` remains the preview source of truth, so there is no duplicate native preview overlay and less CameraX surface pressure.

## Expected good log sequence

Look for all of these during a normal back-camera recording:

```text
I/SiteSnapOverlay: Handshake prebound VideoCapture; waiting for geometry
I/flutter: Realtime CameraX overlay: WAITING_FOR_VIDEO_GEOMETRY
I/flutter: Realtime CameraX overlay: geometry <width>x<height> rotation=<...> mirror=<...>
I/flutter: Realtime CameraX overlay: RASTER_READY generation=<n>
I/SiteSnapOverlay: First realtime overlay frame rendered generation=<n>
I/flutter: Realtime CameraX overlay: ACTIVE generation=<n>
```

After Stop, the healthy single-segment path must **not** contain either of these:

```text
overlay_seq_
Executing FFmpeg: ... overlay=...
```

A legitimate unsupported/error case may still use the legacy fallback. In that case the log now includes the native handshake/prebind failure reason where available.

## Validation commands

From the project root:

```powershell
dart format lib test tool
flutter analyze
flutter test test/realtime_video_overlay_bridge_test.dart
flutter test test/video_recording_production_gate_test.dart
flutter test test/video_processing_realtime_overlay_test.dart
flutter test
flutter build apk --debug
```

Or run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\phase7_1_realtime_overlay_gate.ps1
```

## Physical-device release check

Use a clean debug install and first test a 15–30 second back-camera recording without changing lens or mirror settings.

Pass criteria:

- live preview overlay remains visible;
- `RASTER_READY` appears before recording activation is certified;
- `ACTIVE` appears after CameraX recording starts;
- saved video already contains overlay/watermark immediately after Stop;
- no 0–100 overlay-processing pass appears;
- no `overlay_seq_` / FFmpeg overlay encode appears in log;
- audio/video remain synchronized;
- orientation and overlay position match the preview.

Then repeat with portrait -> landscape, front mirror ON/OFF, and back -> front -> back persistent switch.

## Safety/fallback rules retained

- If pre-bind fails, geometry never resolves, raster generation fails, the native effect errors, or a recorded overlay frame cannot be verified, SiteSnap falls back instead of declaring the raw file complete.
- Realtime-applied and realtime-healthy remain separate metadata so a partially/degraded realtime segment is never blindly instant-saved.
- Existing multi-segment fast-finalization and FFmpeg recovery paths remain available.
