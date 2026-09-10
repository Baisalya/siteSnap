# Phase 7.1.1 — Stop Responsiveness Hotfix

## Evidence from the physical-device log

The Motorola Edge 60 Stylus run proved that the Phase 7.1 CameraX handshake is now working:

- `Handshake prebound VideoCapture; waiting for geometry`
- `Realtime CameraX overlay: geometry 1080x1920 rotation=90 mirror=false`
- `Realtime CameraX overlay: RASTER_READY generation=1`
- `First realtime overlay frame rendered generation=1`
- `Realtime CameraX overlay: ACTIVE generation=1`

The remaining failure was interaction/state timing: CameraX could already be recording while Flutter was still awaiting realtime-overlay certification before publishing `CameraState.isRecording=true`. During that window a second shutter tap could be routed through the Start branch instead of Stop. The device log also showed repeated HWUI image-decoding pressure and occasional `SurfaceProcessorImpl: Timed out waiting canvas post` messages while the realtime bitmap was being refreshed aggressively.

## Changes

1. Recorder state is authoritative.
   - Immediately after `VideoRecordingBackend.start()` succeeds, SiteSnap records `_nativeRecordingStarted=true`.
   - `CameraState.isRecording=true` is published before realtime overlay certification finishes.
   - Realtime certification now runs asynchronously and only toggles `isRealtimeOverlayActive` after success.

2. Stop always wins.
   - Stop accepts either Flutter recording state or the native-recorder latch.
   - On tap it synchronously publishes `isRecording=false`, logs `STOP_REQUESTED`, and gives haptic feedback.
   - The physical CameraX recorder is stopped before overlay-health inspection/finalization.
   - Native overlay status is inspected after Recorder finalization but before bridge cleanup, so instant-save certification remains available.

3. Activation cancellation safety.
   - A token prevents an old async activation from mutating Flutter state after Stop, camera switch, or mirror-segment restart.
   - The bridge also refuses to resurrect itself if `finish()` cancelled the handshake while first-frame polling was still in flight.

4. Lower raster pressure.
   - Realtime overlay raster pushes are capped at 2 FPS (500 ms minimum interval), matching the existing recording overlay sampling cadence.
   - Rapid GPS/compass/settings updates remain coalesced to the newest snapshot.

5. Shutter hit target hardened.
   - Capture/Stop gesture now uses `HitTestBehavior.opaque` over the complete 90x90 shutter area.

## Expected device log

At recording start:

```text
Realtime CameraX overlay: RASTER_READY generation=1
Video recording UI state: RECORDING
Realtime CameraX overlay: ACTIVE generation=1
```

On shutter Stop tap:

```text
Video recording UI state: STOP_REQUESTED
```

Then CameraX should finalize the recording. For a healthy single realtime-overlay segment the production gate should direct-save without generating an `overlay_seq_*` PNG sequence.

## Validation

Run:

```powershell
dart format lib test tool
flutter analyze
flutter test test/realtime_video_overlay_bridge_test.dart
flutter test
flutter build apk --debug
```

Then record 15–30 seconds on the physical Android device and press Stop once. Verify that `STOP_REQUESTED` appears immediately in the log and recording duration stops at that tap.
