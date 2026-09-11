# Phase 8.2 — Professional Zoom Interaction + Animated HUD

## Scope

This phase changes only the camera zoom interaction/presentation path. Photo quality, photo overlay rendering, GPS, subscriptions, project assignment, gallery, and the Phase 7 video compositor are not redesigned here.

## Problem

Phase 8.1 prevented raw pinch events from flooding CameraX, but the visible zoom value still depended on `CameraState.zoom`, which only advances after the native CameraX command completes. On a real device this can make the zoom readout feel one or more camera frames behind the fingers, especially during fast zoom-out. Publishing the full Riverpod camera state for every native zoom acknowledgement can also make the camera screen heavier than necessary.

## Architecture

The zoom path is now split into two feedback rates:

1. **Gesture/HUD rate** — the local `ValueNotifier<double>` follows every pinch target immediately. Only the lightweight zoom HUD repaints.
2. **Native CameraX rate** — the newest zoom ratio is coalesced and applied through `CameraController.setZoomLevel` at approximately one request per display frame. Stale requested ratios are not replayed.
3. **Full CameraState rate** — during an active pinch, accepted native zoom is published to the full Riverpod state at a slower ~80 ms cadence. The final gesture value is always forced into state.

This keeps the preview and camera controller responsive while avoiding a full camera-screen rebuild for every pointer/native frame.

## Professional interaction behavior

- Pinch remains ratio-based and multiplicative (`startZoom * scale`).
- Pinch-in and pinch-out use the same direct-manipulation path.
- Native commands stay serialized/coalesced; no command backlog is accumulated.
- Tiny zoom noise below the existing 0.003 ratio threshold remains ignored.
- The exact final pinch value is committed when the gesture ends.
- Tap on the HUD still performs an eased reset to 1x.
- Light haptic selection feedback occurs when crossing useful zoom landmarks (1x, 2x, 3x, 5x, 10x when those values are reachable). It does not snap the zoom.

## Animated zoom HUD

New file:

`lib/features/camera/presentation/camera_zoom_hud.dart`

The HUD provides:

- animated show/hide,
- subtle scale-up while two-finger zoom is active,
- animated numeric ratio changes,
- a compact logarithmic zoom ruler so the 1x–2x region remains readable even when a device exposes a large digital max zoom,
- an animated position indicator,
- tap-to-reset semantics/accessibility.

The HUD contains no blur filter or heavy image effect; it uses simple Flutter paint/implicit animation to keep thermal/GPU cost low.

## Why ratio zoom is retained for pinch

Android CameraX documents `setZoomRatio()` as the natural API for pinch zoom. `setLinearZoom()` is intended for slider-like UI because it makes field-of-view changes linear. SurveyCam's primary interaction is pinch, so the Flutter camera plugin's ratio-based `setZoomLevel()` remains appropriate.

## Regression boundaries

This phase does not intentionally change:

- CameraX photo resolution or capture mode,
- photo JPEG/overlay save pipeline,
- GPS/location lifecycle,
- flash/focus/exposure behavior,
- Phase 7 realtime video overlay/compositor,
- subscription/premium behavior.

## Physical device acceptance matrix

Run on the Motorola Edge 60 Stylus in release mode:

1. 1x → 3x slowly → 1x slowly.
2. 1x → near max quickly → 1x quickly.
3. Reverse direction several times during one continuous pinch.
4. Hold at 2x and release — no post-release jump/backlog.
5. Tap HUD at >1x — smooth eased return to 1x with visible ratio/ruler animation.
6. Capture photos at 1x, 2x, and 3x — framing should match the settled preview and overlays must still save.
7. Repeat the above after background/resume and front/back camera switching.

Expected: no ANR/crash, no zoom command backlog, no delayed zoom-out catch-up, no full-screen UI jank, and no overlay/photo/video regression.

## Automated gate

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\phase8_2_release_gate.ps1
```
