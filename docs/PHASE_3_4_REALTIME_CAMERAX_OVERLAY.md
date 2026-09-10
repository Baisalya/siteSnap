# SiteSnap Phase 3 + 4 — CameraX Realtime Overlay + WYSIWYG Bridge

## Goal

Remove the normal post-recording overlay encode wait by compositing the overlay inside CameraX before VideoCapture encodes the frame, while preserving the legacy processor as a safe fallback.

## Architecture

### Android CameraX seam

The app remains pinned to `camera_android_camerax 0.7.1+2`, whose Android implementation uses CameraX 1.5.3. The root Android Gradle project overlays only `ProcessCameraProviderProxyApi.java` for that plugin and adds `androidx.camera:camera-effects:1.5.3`. The pub cache is not modified.

When the SiteSnap realtime controller is armed and a bind contains VideoCapture, the same upstream use cases are placed in a `UseCaseGroup` with one `OverlayEffect`. Supported targets are Preview + VideoCapture. Photo-only binds are unchanged.

### Flutter/native bridge

Method channel: `surveycam/realtime_video_overlay`

Flutter remains the visual authoring source. It renders the unified `OverlayRenderSnapshot` to a transparent PNG. Native code caches that bitmap and CameraX composites it into the camera frame.

The raster is regenerated only when the overlay state changes. CameraX continues to composite the cached layer on camera frames, so Flutter does not render a PNG at video frame rate.

### Geometry contract

CameraX supplies crop rect, frame size, rotation and mirroring metadata. Native code maps the display-oriented raster back into the pre-rotation/pre-mirror camera buffer. Flutter additionally limits its authored content to the selected centered 4:3 or 16:9 viewport.

The realtime raster uses the same `OverlayCardRenderer` as the live Flutter overlay and keeps the existing watermark implementation.

## Recording behavior

### Normal Android recording

1. Arm optional realtime effect.
2. Pre-warm VideoCapture.
3. Wait briefly for CameraX frame geometry.
4. Render and send initial transparent overlay raster.
5. Enable CameraX overlay.
6. Start recorder.
7. Coalesce later overlay updates.
8. Stop recorder.
9. Verify native CameraX actually rendered overlay frames and reported no effect error.
10. If verified and no additional mirror/segment transform is required, save directly to the gallery.

No PNG sequence or FFmpeg overlay pass is created in the verified single-segment path.

### Safe fallback

If realtime support, frame geometry, raster upload or activation fails, the realtime bridge is disabled/disarmed. The recording continues through the existing raw recording + background post-processing path.

A realtime segment is marked as already overlaid only after native render verification. The queued job persists this marker, including backward-compatible JSON parsing for older jobs.

The background worker skips overlay generation/application when every segment already contains the realtime overlay. It can still run required segment merge/mirror finalization.

## Scope intentionally retained for Phase 5 + 6

Front-camera mirror correction and multi-camera segment joining can still require FFmpeg finalization. The expensive overlay burn-in is skipped for verified realtime segments, but zero-post-processing for these advanced cases belongs to the orientation/multi-camera hardening phase.

## Files introduced

- `android/camerax_patch/ProcessCameraProviderProxyApi.java`
- `android/camerax_patch/SiteSnapRealtimeOverlayController.java`
- `lib/features/camera/data/realtime_video_overlay_bridge.dart`
- `test/realtime_video_overlay_bridge_test.dart`
- `test/video_processing_realtime_overlay_test.dart`

## Validation commands

```powershell
dart format lib test
flutter analyze
flutter test test/recording_session_coordinator_test.dart test/realtime_video_overlay_bridge_test.dart test/video_processing_realtime_overlay_test.dart test/video_recording_backend_test.dart test/live_overlay_painter_test.dart test/video_watermark_processor_test.dart
flutter test
flutter build apk --debug
```

For device validation, test portrait up/down, both landscapes, 4:3 and 16:9, front/back cameras, recording-time orientation changes, overlay setting changes, GPS/time updates, custom watermark presets, and a long recording. Verify that a normal back-camera single-segment video saves without showing the background overlay-processing stage.
