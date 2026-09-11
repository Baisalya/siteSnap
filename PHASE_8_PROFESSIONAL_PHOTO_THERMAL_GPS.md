# Phase 8 — Professional Photo Capture, Thermal & Low-Latency GPS

## Scope

Phase 8 improves the Android PHOTO path and location availability while preserving the existing VIDEO compositor, subscription/premium behavior, overlay settings, gallery/history and the already-correct camera preview/zoom interaction.

## 1. Photo clarity without a slow shutter

The pinned Flutter CameraX plugin applies the selected preview `ResolutionPreset` to `ImageCapture`. SiteSnap now supplies a project-contained `ImageCaptureProxyApi` patch that separates still-photo resolution from the preview/video preset:

- CameraX `CAPTURE_MODE_MINIMIZE_LATENCY` remains selected for responsive shutter behavior.
- JPEG quality is explicitly 97.
- Still capture requests CameraX's `HIGHEST_AVAILABLE_STRATEGY` using the normal 4:3 output-size set.
- `PREFER_CAPTURE_RATE_OVER_HIGHER_RESOLUTION` intentionally excludes slower ultra/high-resolution sensor modes.
- Preview and VideoCapture keep the existing app preset and are not promoted to a high-resolution camera stream.

On supported phones this should allow a normal full-resolution still surface (for example 4:3 sensor output) while the live preview remains efficient. CameraX can choose a compatible lower size when required by the active use-case combination.

Expected Android log on shutter:

```text
SiteSnapPhoto: Capture surface=<selected resolution> crop=<...> jpegQuality=97 mode=minLatency
```

Record this line during device certification; do not assume a specific megapixel count across devices/lenses.

## 2. Smooth shutter / focus

- Removed the previous up-to-80 ms dependency wait from the physical shutter path.
- Overlay settings, project data and gallery saver still warm in the background.
- A user tap-to-focus position is not re-centered or reset merely because the shutter was pressed.
- The existing UI focus timeout remains the owner of returning AF/AE to automatic behavior.
- Exposure compensation is applied when the user changes it, not redundantly before/after every photo.
- Existing zoom coalescing and preview interaction are unchanged.
- Flash cleanup remains serialized to avoid CameraX teardown races.

## 3. Lower camera thermal load

The pinned plugin initially binds Preview + ImageCapture + ImageAnalysis even when SiteSnap is not consuming image frames. Phase 8 removes `ImageAnalysis` only for that exact idle three-use-case group.

When an image stream is genuinely requested later, the plugin's on-demand ImageAnalysis bind is left intact. VideoCapture behavior and the Phase 7 recording GPU effect remain unchanged.

The patched photo proxy also reuses a two-thread process-lifetime executor instead of creating a new single-thread executor for each shutter press.

## 4. Final photo overlay quality

The existing Flutter overlay renderer remains the source of truth, so card/branding appearance and subscription-controlled overlay features do not diverge.

- Processing cap: 4096 px longest side (was 4032).
- Final JPEG quality: 97 (was 95).
- YUV 4:2:0 JPEG chroma is retained to avoid the CPU/memory/file-size penalty of 4:4:4.
- Parsed default SVG branding is cached instead of reparsed on each save.

No beauty filter, fake HDR, denoise loop, artificial sharpening or new third-party image library was added.

## 5. Faster latitude/longitude

The camera location feed is now cached-first and live-second:

1. Validate service and permission when the stream starts/recoveries occur.
2. Reuse the in-memory last valid fix when it is at most 5 minutes old.
3. Otherwise ask Geolocator for the platform last-known position.
4. Publish a usable cached coordinate immediately.
5. Start the fresh high-accuracy position stream and quietly replace the cached fix.

Coordinates are written to the overlay before weather or reverse-geocoding work. Address and weather use separate request serials and run asynchronously, so slow network/geocoder work does not hold back latitude/longitude.

A transient provider restart no longer clears a valid coordinate to 0/0. The exact 0/0 placeholder is rejected, while valid locations on the equator or Greenwich meridian are accepted.

### Thermal lifecycle

- Android live stream: high accuracy, 5 m distance filter, 2 s requested update interval.
- Paused/hidden/detached app: location tracking disabled and native stream disposed.
- Resumed app: tracking re-enabled immediately.
- `inactive` alone does not kill tracking, avoiding permission-dialog/lifecycle churn.

## Files changed/new

- `android/build.gradle`
- `android/camerax_patch/ImageCaptureProxyApi.java` (new)
- `android/camerax_patch/ProcessCameraProviderProxyApi.java`
- `lib/core/di/providers.dart`
- `lib/features/camera/presentation/camera_screen.dart`
- `lib/features/camera/presentation/camera_viewmodel.dart`
- `lib/features/location/data/location_repository_impl.dart`
- `lib/features/location/domain/location_fix.dart` (new)
- `lib/features/location/domain/location_repository.dart`
- `lib/features/location/presentation/location_viewmodel.dart`
- `lib/features/overlay/presentation/overlay_painter.dart`
- `test/location_fix_policy_test.dart` (new)
- `test/location_stream_bootstrap_test.dart` (new)
- `test/professional_photo_source_contract_test.dart` (new)
- `tool/phase8_release_gate.ps1` (new)

## Automated validation

Run from the project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\phase8_release_gate.ps1
```

The gate is fail-fast. It must not print PASS if analyze/tests/build fail.

## Physical-device certification

Use the same rear lens first. Do not compare different lens modules.

1. Open camera with location permission already granted. Record time until real lat/long appears; repeat after another maps/camera app recently acquired GPS.
2. PHOTO portrait at 1x, daylight, fine text/detail target.
3. PHOTO landscape-left and landscape-right.
4. PHOTO 4:3 then 16:9; verify preview/captured crop is intentional and overlay remains correct.
5. Tap focus near each corner, immediately shutter; verify it does not jump back to center before capture.
6. Exposure +/- then capture.
7. Pinch zoom slowly and quickly, capture at 1x/2x/4x where supported; verify framing remains consistent.
8. 20 repeated captures with 1–2 seconds between shots; no thread explosion, ANR or camera freeze.
9. Leave camera preview open 10 minutes without recording and compare device temperature to the previous production build under the same brightness/location conditions.
10. Background 30 seconds then resume; coordinate may bootstrap from recent fix and should refresh without 0/0 flicker.
11. Disable GPS then re-enable it; verify warning/recovery.
12. Front photo separately; verify existing saved-photo mirror/orientation behavior is unchanged.

For each PHOTO capture collect the `SiteSnapPhoto: Capture surface=...` log. Resolution is device/lens dependent; release criteria is stable capture + materially better detail where the device supports a larger normal JPEG output, not a hard-coded megapixel number.

## Release blockers

Do not ship Phase 8 if any of these occur:

- PHOTO preview or saved orientation regresses.
- zoom becomes jumpy or captured framing materially disagrees with preview.
- repeated capture produces ANR, `FATAL EXCEPTION`, camera freeze, zero-byte image or persistent black preview.
- default photo capture latency becomes visibly worse than the previous build in normal daylight.
- idle thermal behavior worsens materially in controlled comparison.
- cached GPS shows a stale (>5 min) coordinate as current.
- VIDEO rotation/realtime overlay behavior changes relative to the Phase 7.2.3a baseline.
