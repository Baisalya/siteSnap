# Phase 8.3 — Continuous Native Zoom Driver

## Problem

Phase 8.2 removed most UI rebuild pressure, but its native zoom pump still serialized every CameraX zoom request and inserted a fixed 16 ms delay. On devices where `CameraControl.setZoomRatio()` completion follows the repeating capture result, that creates uneven catch-up: the pointer/HUD can move ahead while the preview applies discrete queued ratios.

The HUD also animated each 0.1x text change and the ruler thumb with a 70 ms tween, which visually amplifies jitter during a fast pinch. Flutter scale gestures can also change their cumulative scale origin when the pointer set changes; without rebasing, a second/third finger transition can cause a one-frame zoom jump.

## Phase 8.3 architecture

- Pinch zoom uses CameraX zoom ratio directly.
- Gesture updates are latest-target-wins and synchronized to Flutter display frames with `SchedulerBinding.scheduleFrameCallback`.
- No fixed 16 ms sleep.
- No repository-wide `runExclusive` queue for pinch zoom.
- No waiting for an old zoom future before submitting a newer ratio.
- The final gesture ratio is still awaited once at gesture end.
- CameraX lifecycle/unsupported errors remain guarded and non-fatal.
- Gesture scale is applied incrementally, not against a stale gesture-start zoom.
- Pointer-count changes rebase the scale origin instead of being interpreted as zoom.
- Live zoom number and ruler thumb track the gesture directly; only HUD show/hide/chrome animations remain.
- PHOTO quality, overlay processing, GPS, subscription, and Phase 7 video compositor are out of scope.

## Why superseding is intentional

CameraX documents that a newer zoom operation can cancel the previous zoom future. The pinned `camera_android_camerax 0.7.1+2` implementation explicitly treats `CameraControl.OperationCanceledException` for `setZoomRatio` as successful/non-actionable. Waiting for every prior future therefore defeats CameraX's intended continuous-control behavior.

## Device acceptance matrix

1. Slow 1x -> 3x -> 1x pinch: no visible steps or HUD lag.
2. Fast 1x -> near max -> 1x: preview follows without catch-up after fingers stop.
3. Reverse direction repeatedly in one pinch: no rubber-band jump.
4. Start gesture with one finger then add the second: no initial zoom jump.
5. Add/remove a third finger during pinch: no discontinuity.
6. Hold at a ratio for one second: preview must remain stable, no oscillation.
7. Release at arbitrary ratio: final ratio must not snap backward/forward.
8. Tap zoom HUD reset: camera returns to 1x smoothly.
9. Immediately capture after zoom: saved photo framing must match settled preview.
10. Repeat for front/back cameras and verify zero fatal CameraX/Flutter exceptions.

## Release gate

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\phase8_3_release_gate.ps1
```

The gate is fail-fast and only prints PASS after format, analyze, focused zoom guards, camera/photo/overlay/location/video regressions, full tests, and Android debug build all succeed.
