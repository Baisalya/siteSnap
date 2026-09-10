# Phase 7.2 — Single-Stream Dynamic Rotation GPU Compositor

## Goal

Preserve SiteSnap/SurveyCam's known-good PHOTO and normal camera-preview behavior while making VIDEO recording follow physical portrait/landscape changes inside one continuous CameraX recording. Rotation must not stop/rebind the Recorder, create orientation chunks, stretch frames, or require a post-record rotation concat.

## Production contract

- PHOTO, ImageCapture, and the Flutter camera preview keep their existing orientation contract.
- VideoCapture target rotation and encoder surface dimensions are chosen once at recording start.
- Physical orientation changes during the clip update a recording-only GPU texture transform.
- The same Recorder and MP4 stay active for the entire orientation transition.
- 90/270-degree changes use center-crop `cover` geometry. The fixed encoder surface never changes aspect ratio and camera pixels are not stretched.
- Flutter continues to author the information-card + watermark raster. Camera pixels rotate only after the matching new overlay raster is uploaded to the GL texture, avoiding a camera/overlay one-frame mismatch.
- GPS/time/settings updates remain coalesced at a maximum 2 raster pushes per second. Orientation changes bypass that throttle.
- Stop freezes new raster/orientation commits before Recorder finalization so a late PNG cannot create an unrendered generation after the last encoded frame.
- If GPU setup fails before recording, the effect prebind is explicitly released and the pinned Flutter CameraX recorder is allowed to rebind on its legacy clean path.
- If the GPU pipeline fails after recording has started, the processor first degrades to CameraX's base transform with overlay disabled. Persistent errors invalidate the CameraX input surface per the SurfaceProcessor recovery contract instead of crashing the process.

## Android pipeline

```text
CameraX camera Surface
        |
        v
SiteSnapDynamicVideoSurfaceProcessor
        |
        |-- SurfaceOutput.updateTransformMatrix(CameraX base transform)
        |-- live recording orientation delta
        |-- aspect-aware center-crop cover transform
        |-- Flutter transparent overlay texture blend
        v
constant VideoCapture encoder Surface
        |
        v
one Recorder / one MP4
```

`SiteSnapDynamicVideoEffect` targets VideoCapture only on the pinned CameraX stack. It is project-contained under `android/camerax_patch`; the pub cache is not modified.

## Flutter/native two-phase rotation handoff

For a physical orientation change:

1. `CameraViewModel.updateOrientation()` updates only UI state plus the video backend's recording orientation.
2. The video-specific orientation adapter converts SurveyCam's established PHOTO/UI landscape labels into the CameraX recording convention. The global device-orientation provider is not changed.
3. Flutter rasterizes the overlay for the new video orientation on the fixed encoder canvas.
4. Native confirms the new overlay generation is resident in the GL texture.
5. Only then does Flutter invoke `setDynamicOrientation`.
6. The next GPU frame uses both the new camera transform and matching overlay.

No Recorder stop, VideoCapture target-rotation mutation, or orientation segment restart occurs in this flow.

## Main files

### New

- `android/camerax_patch/SiteSnapDynamicVideoEffect.java`
- `android/camerax_patch/SiteSnapDynamicVideoSurfaceProcessor.java`

### Modified

- `android/camerax_patch/ProcessCameraProviderProxyApi.java`
- `android/camerax_patch/SiteSnapRealtimeOverlayController.java`
- `android/app/src/main/kotlin/com/baishalya/sitesnap/MainActivity.kt`
- `lib/features/camera/data/realtime_video_overlay_bridge.dart`
- `lib/features/camera/data/camera_repository_video_recording_backend.dart`
- `lib/features/camera/domain/video_recording_backend.dart`
- `lib/features/camera/domain/video_capture_orientation.dart`
- `lib/features/camera/presentation/camera_viewmodel.dart`
- `lib/features/overlay/presentation/video_watermark_processor.dart`
- `test/realtime_video_overlay_bridge_test.dart`
- `test/video_capture_orientation_test.dart`

## Expected logs

Initial start:

```text
Realtime CameraX overlay: capture orientation=portraitUp
Realtime CameraX overlay: GPU_TEXTURE_READY generation=1
Realtime CameraX overlay: ACTIVE generation=1
```

During a live rotation:

```text
Realtime CameraX GPU orientation: landscapeRight generation=...
SiteSnapVideoGpu: Dynamic orientation portraitUp -> landscapeRight delta=270 output=1080x1920
```

There must be no orientation-only messages indicating Recorder stop/restart or a new orientation segment.

## Device certification order

Run each test with realtime overlay + SurveyCam branding enabled.

1. PHOTO portrait preview and saved photo.
2. PHOTO landscape-left preview and saved photo.
3. PHOTO landscape-right preview and saved photo.
4. VIDEO portrait-only, 15 seconds.
5. VIDEO landscape-left-only, 15 seconds.
6. VIDEO landscape-right-only, 15 seconds.
7. VIDEO portrait -> landscape-left -> portrait, one clip.
8. VIDEO portrait -> landscape-right -> portrait, one clip.
9. VIDEO landscape -> portrait -> opposite landscape, one clip.
10. Rotate repeatedly, then press Stop during/just after an orientation event.
11. Background/foreground once while recording, then Stop.
12. Front camera mirror ON/OFF separate recordings.

For tests 7–10 verify:

- one logical recording file;
- no orientation-created chunk/concat progress;
- no squashed transition frame;
- no CameraX stop/rebind caused only by physical rotation;
- overlay/card and branding rotate together with camera content;
- PHOTO/preview remain unchanged after recording stops.

## Local validation commands

```powershell
dart format lib test
flutter analyze
flutter test test/video_capture_orientation_test.dart
flutter test test/realtime_video_overlay_bridge_test.dart
flutter test test/video_watermark_processor_test.dart
flutter test
flutter build apk --debug
flutter run
```

This build intentionally keeps `camera_android_camerax` pinned at `0.7.1+2` and CameraX at `1.5.3`. Do not upgrade those dependencies just because newer versions are reported by `flutter pub`.

## Environment note

The packaging environment used for this phase does not contain Flutter/Dart or an Android SDK. Source delimiter audits and Java parser-level smoke checks can be run here, but `flutter analyze`, Flutter tests, Gradle Android compilation, and physical-device certification must be run on the Windows Flutter machine before release.

## Packaging/source audit

Final packaging audit performed after implementation:

- PHOTO/global orientation provider unchanged from the Phase 7.1.5 known-good baseline.
- `camera_screen.dart`, `live_overlay_painter.dart`, `camera_repository_impl.dart`, and `overlay_layout_engine.dart` are byte-identical to the Phase 7.1.5 baseline.
- No portrait/landscape orientation transition path contains Recorder stop/restart or orientation-created segment restart logging.
- `pubspec.yaml` and `pubspec.lock` are unchanged; the pinned CameraX dependency strategy is preserved.
- Delimiter/source-structure checks passed for all modified Dart/Java/Kotlin files.
- `javac` and `kotlinc` parser smoke checks reported no syntax/parser errors; unresolved Android/Flutter symbols are expected because this packaging environment has no Android/Flutter SDK classpath.
- Flutter analyze/tests/APK build and physical-device certification are intentionally not marked passed in this environment.

Use `tool/phase7_2_release_gate.ps1` on the Windows Flutter machine before release.
