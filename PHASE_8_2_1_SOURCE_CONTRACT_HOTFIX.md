# Phase 8.2.1 — Zoom Source-Contract Certification Hotfix

## Why this hotfix exists

The Phase 8.2 release gate passed `flutter analyze`, `camera_interaction_utils_test.dart`, and `camera_zoom_hud_test.dart`, then failed only in `camera_zoom_pipeline_source_contract_test.dart`.

The failed assertion searched `camera_screen.dart` for the exact contiguous text:

`cameraVM.endZoomGesture(finalZoom)`

Dart formatter versions are free to format a chained invocation as either a single line or as:

```dart
cameraVM
    .endZoomGesture(finalZoom)
```

Those forms are semantically identical. A source-contract test must not fail solely because whitespace/newlines changed.

## Fix

`camera_zoom_pipeline_source_contract_test.dart` now creates a whitespace-normalized copy of `camera_screen.dart` for call-shape assertions. It still requires:

- `cameraVM.updateZoomGesture(targetZoom)`
- `cameraVM.endZoomGesture(finalZoom)`
- `CameraZoomHud`
- `ValueNotifier<double> _zoomHudValue`
- coalesced native zoom pipeline fields/timing
- native `setZoomLevel(target)` before published UI zoom state

It still rejects the old direct gesture path `cameraVM.setZoom(zoomForGesture(...`.

## Runtime scope

No production Dart, Android, CameraX, photo, overlay, video, GPS, subscription, or zoom runtime implementation file is modified in this hotfix.

## Run

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\phase8_2_1_release_gate.ps1
```

The gate remains fail-fast. Physical-device zoom validation is still required after the automated gate passes.
