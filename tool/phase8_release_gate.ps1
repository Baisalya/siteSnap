$ErrorActionPreference = 'Stop'

function Invoke-NativeGate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command
    )

    Write-Host $Label -ForegroundColor Cyan
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "Gate failed: $Label (exit code $LASTEXITCODE)"
    }
}

Invoke-NativeGate '== Phase 8: format ==' { dart format lib test }
Invoke-NativeGate '== Phase 8: analyze ==' { flutter analyze }

Write-Host '== Phase 8: focused professional-photo/location tests ==' -ForegroundColor Cyan
Invoke-NativeGate '  professional_photo_source_contract_test.dart' { flutter test test/professional_photo_source_contract_test.dart }
Invoke-NativeGate '  camera_repository_serialization_test.dart' { flutter test test/camera_repository_serialization_test.dart }
Invoke-NativeGate '  camera_interaction_utils_test.dart' { flutter test test/camera_interaction_utils_test.dart }
Invoke-NativeGate '  location_fix_policy_test.dart' { flutter test test/location_fix_policy_test.dart }
Invoke-NativeGate '  location_stream_bootstrap_test.dart' { flutter test test/location_stream_bootstrap_test.dart }
Invoke-NativeGate '  live_overlay_painter_test.dart' { flutter test test/live_overlay_painter_test.dart }
Invoke-NativeGate '  video_watermark_processor_test.dart' { flutter test test/video_watermark_processor_test.dart }

# Protect the recording architecture while touching the shared CameraX provider seam.
Invoke-NativeGate '  dynamic_video_gpu_source_contract_test.dart' { flutter test test/dynamic_video_gpu_source_contract_test.dart }
Invoke-NativeGate '  realtime_video_overlay_bridge_test.dart' { flutter test test/realtime_video_overlay_bridge_test.dart }

Invoke-NativeGate '== Phase 8: full tests ==' { flutter test }
Invoke-NativeGate '== Phase 8: Android debug build ==' { flutter build apk --debug }

Write-Host 'Phase 8 automated gate PASS. Run the physical-device photo/thermal/GPS matrix in PHASE_8_PROFESSIONAL_PHOTO_THERMAL_GPS.md before release.' -ForegroundColor Green
