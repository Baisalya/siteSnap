# Phase 8.1 — Photo Overlay / Capture / Zoom Runtime Hotfix

## Device evidence

The Phase 8.0.1 automated gate passed, but the release device exposed three runtime regressions:

1. The first shutter could time out after 12 seconds.
2. Subsequent image processing logged `Canvas.drawPicture called with non-genuine Picture`, causing photo saves to fall back without the intended overlay/watermark.
3. Pinch zoom felt sluggish, especially zoom-out.

## Root causes and fixes

### 1. Disposed SVG Picture reuse

Phase 8 cached a `Future<PictureInfo>` for the default SurveyCam SVG while each photo job disposed `pictureInfo.picture` after rendering. The next job therefore received the same disposed native `ui.Picture` handle. Phase 8.1 caches only the SVG source string and loads an owned `PictureInfo` per photo render. That picture is disposed only by the render that owns it.

### 2. Over-aggressive still-resolution override

Phase 8 forced `ResolutionStrategy.HIGHEST_AVAILABLE_STRATEGY` and a 4:3 still surface independently of the already-bound Preview. On real CameraX hardware this can create a heavier surface combination and contributed to first-shutter stalls and reduced interactive smoothness. Phase 8.1 keeps `CAPTURE_MODE_MINIMIZE_LATENCY`, JPEG quality 97 and the reusable executor, but honors the resolution selector chosen by the Flutter `CameraController` (`ResolutionPreset.veryHigh` in production).

This preserves high-quality output while restoring one coherent CameraX session contract instead of forcing a second, maximum-size still configuration.

### 3. Zoom event flood / rebuild pressure

The previous pinch path updated Riverpod `CameraState.zoom` for every raw pointer-scale event, even when CameraX had not yet applied that zoom. That could rebuild the full camera screen much faster than native zoom commands were accepted. Phase 8.1 keeps only the newest pending zoom, limits native updates to about one per display frame, skips sub-0.003 noise, and publishes `state.zoom` only after the native `setZoomLevel` command returns.

## Preserved boundaries

- Phase 7 video compositor/recording architecture is unchanged.
- Subscription/premium behavior is unchanged.
- Location bootstrap/thermal policy is unchanged.
- Overlay content/settings behavior is unchanged; only the lifetime of the default SVG render object is corrected.
- Existing Preview aspect/orientation code is unchanged.

## Windows release gate

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\phase8_1_release_gate.ps1
```

After the automated gate passes, test on the physical device:

1. Cold-open camera, pinch 1x -> 3x -> 1x before taking any photo.
2. Take the first photo within 2-3 seconds of camera readiness.
3. Take five photos consecutively with the default SurveyCam logo enabled.
4. Verify every saved photo contains the information overlay and SurveyCam branding.
5. Pinch zoom while a previous photo is being processed in the background; preview should remain responsive.
6. Repeat portrait and landscape photo captures.
