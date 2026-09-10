$ErrorActionPreference = 'Stop'

Write-Host '== Phase 7.2: format ==' -ForegroundColor Cyan
dart format lib test

Write-Host '== Phase 7.2: analyze ==' -ForegroundColor Cyan
flutter analyze

Write-Host '== Phase 7.2: focused tests ==' -ForegroundColor Cyan
flutter test test/video_capture_orientation_test.dart
flutter test test/realtime_video_overlay_bridge_test.dart
flutter test test/video_watermark_processor_test.dart

Write-Host '== Phase 7.2: full tests ==' -ForegroundColor Cyan
flutter test

Write-Host '== Phase 7.2: Android debug build ==' -ForegroundColor Cyan
flutter build apk --debug

Write-Host 'Phase 7.2 automated gate complete. Run the physical-device rotation matrix in PHASE_7_2_SINGLE_STREAM_DYNAMIC_ROTATION_GPU_COMPOSITOR.md before release.' -ForegroundColor Green
