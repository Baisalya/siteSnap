# Phase 7.2.1 — Atomic Orientation Layout Commit + Unified Branding Anchor

## Defects fixed

Physical-device recordings exposed two remaining Phase 7.2 defects:

1. The information card could remain rotated/clipped at the old portrait layout for transitional frames after a portrait -> landscape-left/right turn.
2. SurveyCam branding was explicitly pinned to the opposite bottom corner. On a portrait encoder canvas this could collide with or visually sit inside the wide bottom information card; on landscape it did not match the established preview convention.

The underlying cause was one unnecessary coupling: physical orientation changed both the native camera texture transform **and** Flutter's realtime overlay raster orientation. That forced a rotation through rasterize -> PNG decode -> GL upload -> orientation commit.

## Phase 7.2.1 contract

### Camera pixels

- Physical VIDEO orientation remains recording-only.
- The Recorder and encoder surface stay continuous.
- No orientation-created segment, Recorder restart, target-rotation mutation, or post-record concat is introduced.
- Dynamic orientation is serialized on the same native GL queue that consumes camera frames, so the new camera transform starts on a frame boundary.

### Information card

- Realtime VIDEO overlay is always authored upright in **final encoder-frame coordinates**.
- Device orientation no longer rotates or repositions the raster.
- The selected card position remains bottom-left or bottom-right of the active recording viewport.
- Portrait -> landscape transitions therefore cannot leave a sideways/clipped card while a replacement PNG is being prepared.

### SurveyCam branding

Realtime VIDEO now follows the app's established preview-side convention:

```text
card bottom-left  -> SurveyCam top-left
card bottom-right -> SurveyCam top-right
```

The branding is not placed at the opposite bottom corner and does not inherit physical-device rotation. It shares the same final-frame viewport coordinate system as the card.

PHOTO, ImageCapture, normal Preview painter/layout, and the legacy still/FFmpeg rendering contract are not changed by this phase.

## Orientation fast path

Before:

```text
orientation event
 -> new orientation-dependent overlay raster
 -> PNG encode
 -> Android PNG decode
 -> GL texture upload
 -> setDynamicOrientation
 -> camera finally rotates
```

After:

```text
orientation event
 -> coalesced setDynamicOrientation
 -> native serial GL queue
 -> next camera frame uses new transform
```

Overlay/data updates remain on their normal 500 ms raster budget. If an event changes orientation only and data/settings/viewport are identical, no PNG is generated at all.

## Stop safety

Stop still freezes new raster and orientation work. If one tiny MethodChannel orientation call was already in flight, it is allowed to settle before Recorder.stop(), preventing a late orientation mutation from racing the final encoded frame.

## Main changed files

- `android/camerax_patch/SiteSnapDynamicVideoSurfaceProcessor.java`
- `lib/features/camera/data/realtime_video_overlay_bridge.dart`
- `lib/features/camera/domain/video_recording_backend.dart`
- `lib/features/camera/presentation/camera_viewmodel.dart`
- `lib/features/overlay/presentation/video_watermark_processor.dart`
- `test/realtime_video_overlay_bridge_test.dart`
- `test/realtime_video_overlay_layout_test.dart`

## PHOTO/Preview isolation gate

These files are deliberately unchanged from Phase 7.2:

- `lib/features/camera/presentation/camera_screen.dart`
- `lib/features/overlay/presentation/live_overlay_painter.dart`
- `lib/features/overlay/presentation/preview_overlay_painter.dart`
- `lib/features/overlay/presentation/overlay_layout_engine.dart`
- `lib/features/camera/data/camera_repository_impl.dart`

## Focused tests added/updated

- Orientation command is independent of a replacement overlay raster.
- Orientation-only overlay samples are deduplicated and do not trigger a new PNG.
- Rapid left/right updates are serialized and the newest requested orientation wins.
- Stop cancels an in-flight raster without undoing an already committed orientation.
- Realtime raster bytes are invariant to `portraitUp`, `landscapeLeft`, and `landscapeRight` when visual data/settings are unchanged.
- SurveyCam branding is verified at top-left for a bottom-left card and top-right for a bottom-right card.

## Windows validation

```powershell
dart format lib test
flutter analyze
flutter test test/realtime_video_overlay_bridge_test.dart
flutter test test/realtime_video_overlay_layout_test.dart
flutter test test/video_capture_orientation_test.dart
flutter test test/video_watermark_processor_test.dart
flutter test
flutter build apk --debug
```

Or run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\phase7_2_1_release_gate.ps1
```

## Physical-device certification

Use the Motorola test device and record each case with the information card and SurveyCam branding visible:

1. Portrait-only.
2. Landscape-left-only.
3. Landscape-right-only.
4. Portrait -> landscape-left -> portrait in one clip.
5. Portrait -> landscape-right -> portrait in one clip.
6. Landscape -> portrait -> opposite landscape in one clip.
7. Repeat rotations quickly, then Stop immediately after a turn.
8. Repeat with card position bottom-right.
9. Front camera mirror ON and OFF in separate clips.

Pass criteria:

- one logical MP4;
- no orientation-created processing/chunk/concat;
- card never appears as a clipped vertical strip during a turn;
- SurveyCam never overlaps/sits inside the bottom information card;
- card remains at selected bottom side;
- SurveyCam remains at matching top side;
- no orientation-only `overlay_seq_` / FFmpeg overlay path on a healthy realtime recording;
- PHOTO and normal preview behavior remains unchanged.

## Packaging environment note

The artifact-packaging environment does not contain Flutter/Dart or the Android SDK, so Flutter analyze/tests/APK compilation are not claimed here. Static source/delimiter checks, Java parser-level smoke checks, change-scope isolation checks, and ZIP CRC validation are performed before packaging. Final Android compile and physical-device certification must be run on the Windows Flutter machine.
