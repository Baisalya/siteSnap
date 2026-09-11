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

Invoke-NativeGate '== Phase 8.1: format ==' { dart format lib test }
Invoke-NativeGate '== Phase 8.1: analyze ==' { flutter analyze }

Write-Host '== Phase 8.1: photo overlay/capture/zoom regressions ==' -ForegroundColor Cyan
Invoke-NativeGate '  photo_overlay_runtime_regression_test.dart' { flutter test test/photo_overlay_runtime_regression_test.dart }
Invoke-NativeGate '  professional_photo_source_contract_test.dart' { flutter test test/professional_photo_source_contract_test.dart }
Invoke-NativeGate '  camera_zoom_pipeline_source_contract_test.dart' { flutter test test/camera_zoom_pipeline_source_contract_test.dart }
Invoke-NativeGate '  camera_repository_serialization_test.dart' { flutter test test/camera_repository_serialization_test.dart }
Invoke-NativeGate '  camera_interaction_utils_test.dart' { flutter test test/camera_interaction_utils_test.dart }
Invoke-NativeGate '  live_overlay_painter_test.dart' { flutter test test/live_overlay_painter_test.dart }
Invoke-NativeGate '  video_watermark_processor_test.dart' { flutter test test/video_watermark_processor_test.dart }

Write-Host '== Phase 8.1: location/video regression guards ==' -ForegroundColor Cyan
Invoke-NativeGate '  location_fix_policy_test.dart' { flutter test test/location_fix_policy_test.dart }
Invoke-NativeGate '  location_stream_bootstrap_test.dart' { flutter test test/location_stream_bootstrap_test.dart }
Invoke-NativeGate '  dynamic_video_gpu_source_contract_test.dart' { flutter test test/dynamic_video_gpu_source_contract_test.dart }
Invoke-NativeGate '  realtime_video_overlay_bridge_test.dart' { flutter test test/realtime_video_overlay_bridge_test.dart }

Invoke-NativeGate '== Phase 8.1: full tests ==' { flutter test }
Invoke-NativeGate '== Phase 8.1: Android debug build ==' { flutter build apk --debug }

Write-Host 'Phase 8.1 automated gate PASS. Verify repeated photo overlay saves, first-shutter latency, and pinch zoom on the physical device.' -ForegroundColor Green
