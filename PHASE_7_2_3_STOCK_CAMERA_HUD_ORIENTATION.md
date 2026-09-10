# Phase 7.2.3 — Stock-Camera Pass-Through + Live HUD Orientation

## Why Phase 7.2.2 still looked wrong

The two device recordings used for this correction showed both start-orientation cases:

- `1000175648.mp4`: 1920x1080 start canvas.
- `1000175649.mp4`: 1080x1920 start canvas.

The Phase 7.2.2 compositor was trying to quarter-turn the camera texture inside that already-running fixed MP4 canvas. A rectangular 1920x1080 frame cannot become 1080x1920 midway through one normal Recorder track. FIT_CENTER therefore produced black/shrunken framing, while a fill transform would necessarily zoom/crop. Neither behaves like a normal camera recording.

Android CameraX also documents that `VideoCapture.setTargetRotation()` has no effect on an ongoing `Recorder` recording; it affects recordings started later. Therefore recording orientation is selected at start and the current MP4 canvas remains fixed.

## Phase 7.2.3 production contract

### Camera pixels

Camera pixels are no longer dynamically rotated, scaled, fitted, cropped, or letterboxed by SiteSnap.

```text
CameraX SurfaceOutput transform
          |
          |  unchanged camera pixels
          v
SiteSnap GPU compositor
          |
          |  alpha blend transparent HUD only
          v
fixed Recorder encoder surface
```

`SiteSnapDynamicVideoSurfaceProcessor` now samples the camera only through CameraX's own `SurfaceOutput.updateTransformMatrix(...)` result. There is no SiteSnap `uDynamicMatrix`, FIT_CENTER scale, COVER scale, or quarter-turn camera transform.

This intentionally matches stock-camera single-recording semantics: the orientation chosen when recording starts owns the encoded canvas for the life of that MP4.

### GPS card + SurveyCam branding

The overlay is app-owned, so it can follow physical device orientation without modifying camera pixels.

At recording start Flutter stores the physical start orientation. Each live overlay update is converted to a relative HUD orientation:

```text
record start portrait + current portrait        -> portraitUp HUD
record start portrait + current landscape-left -> landscapeLeft HUD
record start portrait + current landscape-right-> landscapeRight HUD
record start landscape + current portrait       -> opposite relative quarter-turn
```

Flutter renders the information card and SurveyCam branding into a transparent raster already positioned in the fixed encoder canvas. The existing PHOTO/preview `OverlayFrameGeometry` orientation transform is reused for HUD geometry only.

The native GPU compositor then performs a plain alpha blend. Camera coordinates and HUD coordinates are intentionally independent.

## Transition behavior

- Normal time/GPS/settings changes keep the 500 ms coalescing budget.
- A physical orientation change is urgent and bypasses that budget.
- An older data raster that is still sleeping or rendering is invalidated by an epoch token.
- Only the newest orientation raster may reach `setOverlayPng`.
- Native PNG decode remains on `SiteSnap-Overlay-Decode`, not the GL frame thread.
- Texture replacement occurs on the serialized GL executor, so there is no partially uploaded HUD frame.
- Normal Stop freezes immediately. If a physical orientation HUD is already in flight, Stop gives it a bounded 180 ms commit window plus up to 120 ms render settle before freezing; stale results are still rejected by the health gate.

## Direct-save health gate

Phase 7.2.3 additionally checks:

- latest overlay generation rendered;
- latest expected relative HUD orientation uploaded;
- native `cameraTransformMode == cameraxBasePassThrough`;
- native `dynamicScaleMode == none`;
- no current GPU/native error;
- no consecutive Flutter bridge update failure.

A mismatch falls back instead of falsely certifying the clip as a healthy instant-save realtime recording.

## PHOTO / preview isolation

Do not change the global PHOTO/preview orientation mapping for this phase. In particular the established CameraScreen, ImageCapture path, and live overlay painter are not redesigned by Phase 7.2.3.

## Expected logs

At recording start:

```text
Video recording orientation locked: physical=portraitUp capture=portraitUp
Realtime CameraX overlay: capture orientation=portraitUp
Realtime CameraX overlay: GPU_TEXTURE_READY generation=...
Realtime CameraX overlay: ACTIVE generation=...
```

On a physical turn:

```text
Realtime CameraX overlay layout: landscapeLeft (relative=landscapeLeft)
SiteSnapVideoGpu: Overlay layout uploaded generation=... relativeOrientation=landscapeLeft
```

For a landscape-start clip returning to portrait, the relative label can be the opposite landscape quarter-turn. That is expected because the MP4 canvas is anchored to recording start.

Old Phase 7.2.2 logs such as `scale=FIT_CENTER` or a dynamic camera rotation delta must not appear.

## Physical-device certification matrix

Use the Motorola test device and record at least 10–15 seconds for each case:

1. VIDEO portrait-only.
2. VIDEO landscape-left-only.
3. VIDEO landscape-right-only.
4. Start portrait -> turn landscape-left -> return portrait.
5. Start portrait -> turn landscape-right -> return portrait.
6. Start landscape-left -> turn portrait -> return landscape-left.
7. Start landscape-right -> turn portrait -> return landscape-right.
8. Landscape-left -> portrait -> landscape-right in one clip.
9. Rapid left/right turns, then Stop immediately after the last turn.
10. Front camera mirror ON and OFF in separate clips.

For transition cases verify all of the following:

- one continuous MP4 for orientation-only changes;
- no FFmpeg orientation concat/re-encode for a healthy realtime segment;
- no artificial camera zoom/crop;
- no FIT_CENTER black/shrunken camera frame introduced by SiteSnap;
- camera motion/FOV looks the same as the underlying CameraX recording;
- GPS card changes orientation/anchor with the physical phone;
- SurveyCam branding follows the same logical HUD side;
- no old portrait card remains permanently locked after entering landscape;
- no old landscape card remains permanently locked after returning portrait;
- Stop remains immediate in steady-state; directly after a rotation only the bounded HUD settle window above is allowed, and the saved video opens normally.

## Windows automated gate

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\phase7_2_3_release_gate.ps1
```

The release script is fail-fast. It must print the final PASS line only after format, analyze, focused tests, full tests, and Android debug build all succeed.
