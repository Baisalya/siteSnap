# Phase 7.1.5 — Photo/Preview Isolation + Stable Recording Orientation Lock

## Why this hotfix exists

Phases 7.1.3/7.1.4 fixed video orientation by changing the shared accelerometer orientation mapping and by automatically stopping/restarting CameraX video segments when the phone crossed portrait/landscape axes. Device testing showed two unacceptable regressions:

1. PHOTO / idle CameraPreview orientation changed even though the photo pipeline was already correct before the video refactor.
2. Mid-recording rotation produced visible discontinuities, segment hand-off glitches, and extra CameraX stop/rebind/start operations.

The production rule in this hotfix is **video changes must not rewrite photo/preview orientation semantics**.

## Restored photo contract

`lib/core/utils/device_orientation_provider.dart` is restored to the Phase 7.1.1 last-known-good implementation. It remains the source used by PHOTO capture, photo overlay rendering and the camera UI. Video code never modifies this global provider or its landscape labels.

The Phase 7.1.4 `restorePreviewPipeline()` native rebind path is removed. Recording cleanup no longer manually rebuilds Preview/ImageCapture use cases behind Flutter's camera controller.

## Recording-only orientation adapter

A new recording-only helper lives at:

`lib/features/camera/domain/video_capture_orientation.dart`

It converts the established UI/photo orientation labels into the CameraX VideoCapture target-rotation contract. The landscape labels are swapped **only for VideoCapture**. PHOTO continues using its original semantics unchanged.

Native `VideoCapture.setTargetRotation()` is applied only during the realtime-video handshake before VideoCapture is pre-bound. Preview and ImageCapture target rotation are never mutated by SiteSnap realtime-video code.

## Mid-recording rotation policy

A standard MP4 track has a stable coded frame geometry and display transform. CameraX 1.5.3 also does not change an already-running Recorder's target rotation. Automatically finalizing one Recorder and starting another every time the phone rotates caused the visible "chunk/chunk" behavior observed on device.

Phase 7.1.5 therefore locks the encoded orientation for the entire logical recording at Record start:

- Portrait start -> portrait recording until Stop.
- Landscape-left start -> landscape recording until Stop.
- Landscape-right start -> landscape recording until Stop.
- Rotating the phone while the clip is running does **not** stop/restart CameraX and does not create an orientation segment boundary.
- Overlay data (time/GPS/etc.) continues updating, but its encoded orientation remains locked to the recording axis.

This is intentionally the stability-first production behavior. Seamless dynamic orientation inside one ordinary MP4 would require a dedicated full-frame GPU SurfaceProcessor that rotates/scales the camera texture while keeping one encoder surface; it should not be approximated by Recorder segmentation.

## Crash/race reduction

Removing orientation-driven Recorder restarts removes the highest-risk native command overlap:

`stop -> target rotation -> prebind -> start` during an active shutter session.

Start/Stop responsiveness protections from Phase 7.1.1 remain intact, including the native-recorder latch, immediate STOP_REQUESTED UI state, realtime-overlay health verification and 500 ms overlay raster cadence.

## Required device validation

Run on the Flutter workstation:

```powershell
dart format lib test
flutter analyze
flutter test test/video_capture_orientation_test.dart test/realtime_video_overlay_bridge_test.dart
flutter test
flutter build apk --debug
```

Then test on the physical device:

1. PHOTO portrait -> preview correct, saved photo correct, overlay correct.
2. PHOTO landscape-left -> preview/photo behavior matches the pre-video-refactor build.
3. PHOTO landscape-right -> same.
4. VIDEO portrait start -> Stop -> direct save, realtime overlay, no FFmpeg overlay pass.
5. VIDEO landscape-left start -> upright landscape final file.
6. VIDEO landscape-right start -> upright landscape final file.
7. VIDEO portrait start -> rotate phone several times -> Stop. There must be no automatic segment restart, no chunk/jump handoff and no CameraX orientation-rebind crash. The clip keeps its start orientation by design.
8. Rapid rotate + Stop / background + resume -> recording must stop safely without resurrecting recording UI.

Expected video-start log includes:

```text
Video recording orientation locked: ui=<...> capture=<...>
Realtime CameraX overlay: capture orientation=<...>
Realtime CameraX overlay: ACTIVE generation=<n>
```

There must be no `Recording orientation transition:` or `Recording orientation segment restarted:` log in this release.
