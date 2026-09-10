> **Superseded by Phase 7.1.5.** Runtime orientation behavior no longer uses mid-recording axis restarts or global photo-orientation remapping. This file is retained only as historical context.

# Phase 7.1.3 — Landscape Direction + Mid-recording Rotation Hotfix

## Device failures reproduced

1. A recording that starts in landscape is horizontal, but the camera scene is 180° on the wrong landscape side while the realtime overlay stays readable.
2. A recording that starts in portrait and is physically rotated to landscape while recording becomes sideways/misaligned because the running Recorder keeps its original target rotation.
3. In landscape realtime recordings the default SurveyCam branding can overlap the bottom-left information card.

## Root causes

### Landscape left/right sensor labels were reversed

Android's canonical sensor frame keeps +X pointing to the hardware right edge and +Y toward the hardware top. On a portrait-natural handset, rotating the device 90° counter-clockwise (Flutter `DeviceOrientation.landscapeLeft`) puts gravity on +X. The previous provider mapped +X to `landscapeRight`, so once CameraX target rotation became explicit the encoded landscape video was 180° wrong.

`deviceOrientationFromAccelerometer()` is now a pure/tested mapping:

- `y > threshold` -> portraitUp
- `y < -threshold` -> portraitDown
- `x > threshold` -> landscapeLeft
- `x < -threshold` -> landscapeRight

### CameraX target rotation cannot reorient an ongoing Recorder

CameraX `VideoCapture.setTargetRotation()` affects recordings started after the call; it does not change the orientation contract of the currently running Recorder. SiteSnap therefore cannot safely change portrait/landscape dimensions inside one active native MP4 by only updating `targetRotation`.

Phase 7.1.3 uses a controlled hidden segment boundary after a physical orientation has remained stable for 450 ms:

1. keep the current realtime overlay raster frozen to the current native segment orientation;
2. finalize the current CameraX segment;
3. set the new physical capture orientation;
4. pre-bind VideoCapture and obtain new geometry;
5. prepare the new realtime raster;
6. start the next CameraX segment;
7. continue recording UI/timer as one logical recording.

At final Stop, fixed-orientation recordings still qualify for instant save. A logical recording that changed portrait/landscape has multiple native dimensions and is normalized into one playback canvas during background finalization. Since its overlay is already burned realtime, this is only orientation/segment finalization — the old PNG overlay sequence is not generated again.

Android multi-segment normalization now uses the existing hardware encoder selection (`h264_mediacodec`) instead of hard-coded `libx264` when available.

## Branding collision

For display-oriented realtime landscape rasters, branding now uses the bottom corner opposite the information card. Portrait behavior is unchanged.

## Expected logs

Landscape-start recording should show the physically correct side, for example:

```
Video capture orientation: physical=landscapeLeft ...
SiteSnapOverlay: Handshake prebound VideoCapture; captureOrientation=landscapeLeft targetRotation=1
Realtime CameraX overlay: geometry 1920x1080 ...
Realtime CameraX overlay: ACTIVE generation=...
```

When rotating during recording:

```
Recording orientation transition: portraitUp -> landscapeLeft
Recording orientation segment restarted: landscapeLeft
```

No orientation transition is started for brief sensor wobble shorter than 450 ms.

## Validation commands

```powershell
dart format lib test
flutter analyze
flutter test test/device_orientation_provider_test.dart
flutter test test/realtime_video_overlay_bridge_test.dart test/video_watermark_processor_test.dart
flutter test
flutter build apk --debug
```

## Device matrix

- Portrait start -> Stop: direct save, upright.
- Landscape-left start -> Stop: direct save, correct side, upright card and branding.
- Landscape-right start -> Stop: direct save, correct side, upright card and branding.
- Portrait start -> hold landscape-left > 450 ms -> Stop: automatic orientation segment; final merged playback has upright landscape section inside the portrait-start canvas.
- Landscape start -> hold portrait > 450 ms -> Stop: automatic orientation segment; final merged playback has upright portrait section inside the landscape-start canvas.
- Quick tilt and return within 450 ms: no segment boundary.

Flutter/Dart tooling was not available in the packaging environment, so the commands above must be run on the target Flutter workstation before release.
