# Phase 7.2.2 — Live Overlay Orientation + Full-FOV Fit-Center Rotation

## Why this phase exists

Phase 7.2.1 deliberately stopped rebuilding/rotating the Flutter PNG when the phone turned. That removed the delayed/clipped overlay race, but it also made the encoded GPS card and SurveyCam branding stay locked to the orientation in which recording started.

Phase 7.2 also used a quarter-turn `cover` transform for camera pixels. `cover` avoids stretch but necessarily zoom-crops when a portrait encoder canvas must temporarily show landscape content (or vice versa).

Phase 7.2.2 fixes both without bringing back orientation-created recording segments or expensive PNG work.

## Final recording contract

- One CameraX Recorder / one VideoCapture / one MP4 stays active for the clip.
- PHOTO and normal Flutter preview remain outside the recording GPU effect.
- Flutter still rasterizes the information card + SurveyCam brand only when data/settings actually change.
- An orientation-only event does **not** generate another PNG.
- Native GL transforms **camera + the cached overlay texture together** on the same frame queue.
- Therefore card and SurveyCam branding move/rotate atomically with the recorded scene.
- Quarter-turns use **FIT_CENTER**, not FILL/COVER:
  - no extra zoom crop caused by SiteSnap rotation;
  - no aspect-ratio stretch;
  - full CameraX VideoCapture frame remains visible;
  - black letterbox/pillarbox is used for the unavoidable unused area when a fixed MP4 canvas shows the opposite aspect orientation.
- 0° and 180° transitions do not need fit bars because source/output aspect is unchanged.

## Why black bars are the correct no-crop behavior

An H.264/MP4 video track has one encoded width/height for the recording. A 1080x1920 track cannot become 1920x1080 halfway through the same CameraX Recorder session. When the physical phone turns 90 degrees, there are only three mathematically possible policies inside the fixed canvas:

1. stretch the picture (wrong geometry),
2. fill the canvas by cropping/zooming,
3. fit the whole rotated frame and leave unused space.

This phase chooses option 3. CameraX itself still chooses the camera/video profile and its normal crop rectangle; Phase 7.2.2 only removes the **additional dynamic-rotation crop** previously introduced by SiteSnap's GPU compositor.

## GPU change

Old Phase 7.2.1 shader path:

```text
output UV ──> dynamic camera matrix ──> CameraX texture
output UV ────────────────────────────> overlay texture
```

The two layers had different orientation ownership, so the overlay was locked.

New Phase 7.2.2 shader path:

```text
                     ┌──> CameraX base transform ──> camera texture
output UV ──> dynamic UV
                     └─────────────────────────────> overlay texture
```

Both layers consume the same `vDynamicCoord`. The same GL queue owns the orientation transition, so no raster-upload race is required for a phone turn.

## Main production changes

### `SiteSnapDynamicVideoSurfaceProcessor.java`

- added `uDynamicMatrix` as a first-class shader uniform;
- camera texture receives `CameraXMatrix * DynamicMatrix`;
- overlay texture receives the same dynamic coordinate;
- replaced quarter-turn cover scale with `fitScale = min(...)`;
- detects dynamic coordinates outside `[0,1]` and paints those pixels black instead of clamping/smearing edge pixels;
- dynamic log now reports `scale=FIT_CENTER overlayFollow=true`.

### Flutter bridge

No orientation-only raster regeneration was reintroduced. The existing serialized `setDynamicOrientation` command remains the lightweight orientation signal. Data/time/GPS/settings refreshes remain on the coalesced PNG update path.

## Expected device log

For a portrait-start recording rotated to landscape:

```text
Realtime CameraX GPU orientation: landscapeLeft
SiteSnapVideoGpu: Dynamic orientation portraitUp -> landscapeLeft delta=90 scale=FIT_CENTER overlayFollow=true output=1080x1920
```

Or the corresponding `landscapeRight`/`delta=270` direction depending on the device mapping.

There must be no orientation-only Recorder stop/start, segment close, FFmpeg concat, or `overlay_seq_` generation on the healthy realtime path.

## Physical-device certification

Run these on the Motorola test device after the automated gate:

1. VIDEO portrait-only — overlay/card/brand unchanged from known-good portrait.
2. VIDEO landscape-left-only — unchanged from known-good static landscape behavior.
3. VIDEO landscape-right-only — unchanged from known-good static landscape behavior.
4. Portrait -> landscape-left -> portrait in one clip.
5. Portrait -> landscape-right -> portrait in one clip.
6. Landscape-left -> portrait -> landscape-right in one clip.
7. Repeat left/right turns quickly, then Stop immediately after a turn.
8. Front camera mirror ON and OFF, with one quarter-turn each.

For tests 4–8 verify:

- one MP4;
- GPS card and SurveyCam brand rotate/move with camera content on the same transition;
- no overlay locked in the recording-start orientation;
- no SiteSnap-added zoom crop on the quarter-turn;
- no stretched/squashed frame;
- black fit area is allowed/expected when start/current orientations have opposite aspect ratios;
- no edge-pixel smear in the fit area;
- no post-stop 0–100 overlay processing on a healthy realtime recording.

## Automated gate

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\phase7_2_2_release_gate.ps1
```

The gate is fail-fast and runs format, analyze, focused tests, all tests, and debug APK build.

## Dependency policy

No CameraX/Flutter-camera dependency upgrade is part of this phase. Keep the certified pinned stack (`camera_android_camerax 0.7.1+2`, CameraX 1.5.3) while validating this targeted compositor change.
