> **Superseded by Phase 7.1.5.** Runtime orientation behavior no longer uses mid-recording axis restarts or global photo-orientation remapping. This file is retained only as historical context.

# Phase 7.1.4 — Preview Restore + Rotation Stability

## User-observed regressions addressed

1. After a landscape/orientation-changing recording, the idle CameraPreview could remain sideways because the recording-only VideoCapture stayed bound with its explicit target rotation.
2. A portrait→landscape transition in the final merged MP4 showed a very short squash/jump around the CameraX surface rebuild boundary.
3. Rapid rotate + Stop could overlap native Recorder stop/rebind/start commands.

## Changes

- Native `restorePreviewPipeline()` unbinds recording-only VideoCapture after finalization, resets its target rotation to portrait-neutral, and rebinds missing non-video use cases.
- Flutter realtime bridge invokes preview restore as part of final cleanup.
- Stop waits (max 4 s fail-safe) for any in-flight orientation segment rebuild before issuing the final native Stop. UI STOP_REQUESTED still publishes immediately.
- Orientation stability delay reduced from 450 ms to 240 ms.
- Multi-segment orientation finalization detects portrait/landscape axis boundaries, trims 100 ms of unstable CameraX warm-up/tear-down frames around those boundaries, resets PTS, resamples audio, and emits constant 30 FPS before concat.
- Camera switches that keep the same orientation axis are not boundary-trimmed by this logic.

## Expected behavior

- Fixed-orientation recordings: realtime overlay + direct save remains unchanged.
- Rotate while recording: hidden segment rebuild remains necessary on CameraX 1.5.3, but the final merged transition is a clean hard orientation cut rather than a stretched/squashed surface frame.
- After Stop: idle preview returns to the normal preview pipeline instead of retaining the recording target rotation.
- Rapid rotate/Stop: native Recorder commands are serialized rather than overlapping.

## Validation on Flutter machine

```powershell
dart format lib test
flutter analyze
flutter test test/realtime_video_overlay_bridge_test.dart test/video_watermark_processor_test.dart test/device_orientation_provider_test.dart
flutter test
flutter build apk --debug
```

Device matrix: portrait-only, landscape-left-only, landscape-right-only, portrait→landscape, landscape→portrait, rapid rotate twice, rotate+immediate Stop, rotate+background/resume, front mirror ON/OFF.

## Explicit segment orientation metadata

Each finalized native segment now carries the `DeviceOrientation` it was recorded with. The background finalizer therefore does not have to guess whether a boundary is a camera switch or a portrait/landscape rotation from dimensions alone. JSON remains backward compatible: older queued jobs simply decode the new field as `null` and fall back to dimension-based detection.

## Uploaded regression clip findings

The supplied regression MP4 is 1080x1920 H.264. Its average video frame rate is lower than the 30 fps target and there are short doubled frame intervals around the orientation boundary. Phase 7.1.4 normalizes re-encoded orientation-transition jobs to constant 30 fps and removes the CameraX surface handoff edge frames while preserving fixed-orientation direct-save behavior.
