> **Superseded by Phase 7.1.5.** Runtime orientation behavior no longer uses mid-recording axis restarts or global photo-orientation remapping. This file is retained only as historical context.

# Phase 7.1.2 — Landscape Target Rotation Hotfix

## Symptom

Portrait recordings are upright, but a recording started while the phone is held horizontally is saved as a portrait 1080×1920 video with the camera scene rotated 90 degrees. The realtime information overlay can remain readable, which makes the camera pixels and overlay look as if they use different orientation systems.

## Root cause

SiteSnap intentionally keeps the Android Activity/UI portrait-locked. `camera_android_camerax` derives its default video target rotation from the Activity display/configuration. A portrait-locked Activity therefore leaves `VideoCapture` targeting portrait even while the physical phone is horizontal.

The CameraX `OverlayEffect` then correctly processes the stream it is given, but that stream is already normalized to the wrong portrait output axis. Phase 7.1 fixed the realtime-overlay geometry handshake; this hotfix fixes the encoded video target axis before that handshake binds VideoCapture.

`CameraController.value.deviceOrientation` is not used as the physical-grip authority here because the pinned CameraX plugin's `DeviceOrientationManager` computes UI orientation from Android `Configuration` and display rotation. SiteSnap already has an accelerometer-backed `deviceOrientationProvider`, which continues to report the physical grip while the Activity is portrait-locked.

## New recording-start contract

1. Read SiteSnap's accelerometer-backed physical `DeviceOrientation` when the logical recording starts.
2. Freeze that orientation for the logical recording/segments.
3. Send it to the native realtime-overlay handshake.
4. Convert it to Android `Surface` target rotation:
   - portraitUp -> ROTATION_0
   - landscapeLeft -> ROTATION_90
   - portraitDown -> ROTATION_180
   - landscapeRight -> ROTATION_270
5. Call `VideoCapture.setTargetRotation(...)` before the Phase 7.1 VideoCapture pre-bind.
6. Pre-bind VideoCapture and obtain geometry for that output axis.
7. Rasterize/enable the realtime overlay against the resulting geometry.
8. Start Recorder.

This keeps Flutter preview behavior unchanged. Only the encoded VideoCapture target axis is corrected.

## Expected logs

Landscape-left start should contain lines similar to:

```text
Video capture orientation: physical=landscapeLeft overlay=landscapeLeft
Realtime CameraX overlay: capture orientation=landscapeLeft
SiteSnapOverlay: Handshake prebound VideoCapture; captureOrientation=landscapeLeft targetRotation=1; waiting for geometry
Realtime CameraX overlay: geometry 1920x1080 rotation=0 mirror=false
Realtime CameraX overlay: RASTER_READY generation=1
Realtime CameraX overlay: ACTIVE generation=1
```

Landscape-right uses `targetRotation=3`. Exact CameraX transformation degrees can vary with sensor/lens orientation, but the saved playback must be visually upright and landscape.

## Regression checks

Run:

```powershell
dart format lib test
flutter analyze
flutter test test/realtime_video_overlay_bridge_test.dart
flutter test
flutter build apk --debug
```

Then on a physical Android device:

1. Portrait-up, back camera, 10 seconds -> upright portrait video.
2. Landscape-left, back camera, 10 seconds -> upright landscape video.
3. Landscape-right, back camera, 10 seconds -> upright landscape video, not upside down.
4. Repeat landscape with front camera mirror OFF and ON.
5. Stop each recording and confirm the healthy single-segment path still direct-saves without `overlay_seq_` / FFmpeg overlay processing.

## Scope note

The encoded axis is frozen at recording start so all segments of a logical recording stay compatible for fast finalization. Rotating the phone to a different physical orientation in the middle of one recording is a separate policy problem and is not silently treated as a new MP4 axis in this hotfix.
