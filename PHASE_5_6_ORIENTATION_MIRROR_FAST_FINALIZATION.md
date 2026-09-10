# SiteSnap Phase 5 + Phase 6

## Orientation / mirroring hardening

- Keeps `camera_android_camerax` pinned to `0.7.1+2` and CameraX `1.5.3`.
- Front-video mirror policy is applied at `VideoCapture.Builder` time with
  `MIRROR_MODE_ON_FRONT_ONLY` or `MIRROR_MODE_OFF`.
- The Flutter/native bridge verifies whether the current `VideoCapture` was
  built with the requested mirror mode.
- If the mode differs, SiteSnap recreates the current CameraX controller once
  before recording starts. Unsupported platforms/devices retain the existing
  per-segment FFmpeg mirror fallback.
- CameraX OverlayEffect frame mirroring/rotation remains the WYSIWYG transform
  source for the live overlay.
- A persistent native file that contains front/back switches is explicitly
  marked so legacy front-only portrait correction is never applied to the
  entire mixed-lens file.

## Multi-camera fast finalization

- Android recordings start with persistent recording enabled.
- While recording, normal front/back lens switches first use
  `CameraController.setDescription` and keep the same active recorder/file.
- If persistent switching is unsupported or unsafe, SiteSnap falls back to the
  existing segment boundary flow.
- Changing the front-mirror preference during an active front recording keeps a
  deliberate segment boundary because mirror mode is a VideoCapture builder
  configuration.
- Multi-segment finalization probes codec/profile/pixel format/time base,
  resolution, frame rate, rotation and audio layout.
- Definitively compatible segments with no pending transform use FFmpeg concat
  demuxer + `-c copy`; no video decode/re-encode occurs.
- Unknown/mismatched metadata, required hflip, or orientation correction uses
  the existing normalization/re-encode fallback.

## Validation commands

Run from the project root on the Flutter development machine:

```powershell
dart format lib test
flutter analyze
flutter test test/recording_session_coordinator_test.dart test/realtime_video_overlay_bridge_test.dart test/video_fast_finalization_test.dart test/video_processing_realtime_overlay_test.dart test/video_recording_backend_test.dart test/video_watermark_processor_test.dart
flutter test
flutter build apk --debug
```

## Device regression matrix

1. Back camera, portrait -> rotate landscape -> portrait during one recording.
2. Front camera, mirror OFF.
3. Front camera, mirror ON.
4. Back -> front -> back while recording, mirror OFF: recording must remain one file on supported CameraX devices.
5. Back -> front -> back while recording, mirror ON: front portion must be mirrored without a post-record hflip on supported devices.
6. Toggle front mirror while actively recording on front camera: segment boundary is expected; finalization should stream-copy when segment signatures match.
7. Force/observe native realtime-overlay fallback and confirm legacy processing still saves a usable video.
8. Record with repeated orientation and lens changes and verify overlay location remains WYSIWYG.
