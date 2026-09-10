$ErrorActionPreference = 'Stop'

Write-Host '== Phase 7: format check =='
dart format lib test tool
dart format --output=none --set-exit-if-changed lib test

Write-Host '== Phase 7: analyzer =='
flutter analyze

Write-Host '== Phase 7: focused recording tests =='
flutter test `
  test/recording_session_coordinator_test.dart `
  test/realtime_video_overlay_bridge_test.dart `
  test/recording_storage_guard_test.dart `
  test/video_recording_production_gate_test.dart `
  test/video_fast_finalization_test.dart `
  test/video_processing_realtime_overlay_test.dart `
  test/video_recording_backend_test.dart `
  test/video_watermark_processor_test.dart

Write-Host '== Phase 7: full test suite =='
flutter test

Write-Host '== Phase 7: Android debug build =='
flutter build apk --debug

Write-Host 'PHASE 7 SOURCE GATE PASSED. Complete the physical-device matrix before production release.'
