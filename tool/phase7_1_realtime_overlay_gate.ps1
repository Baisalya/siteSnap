$ErrorActionPreference = "Stop"

Write-Host "[1/5] Formatting Dart sources..."
dart format lib test tool

Write-Host "[2/5] Running analyzer..."
flutter analyze

Write-Host "[3/5] Running focused Phase 7.1 tests..."
flutter test test/realtime_video_overlay_bridge_test.dart
flutter test test/video_recording_production_gate_test.dart
flutter test test/video_processing_realtime_overlay_test.dart

Write-Host "[4/5] Running full test suite..."
flutter test

Write-Host "[5/5] Building Android debug APK..."
flutter build apk --debug

Write-Host "Phase 7.1 static/automated release gate passed. Complete the physical-device checklist in PHASE_7_1_CAMERAX_GEOMETRY_HANDSHAKE.md."
