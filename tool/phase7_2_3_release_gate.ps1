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

Invoke-NativeGate '== Phase 7.2.3: format ==' { dart format lib test }
Invoke-NativeGate '== Phase 7.2.3: analyze ==' { flutter analyze }

Write-Host '== Phase 7.2.3: focused stock-camera/HUD tests ==' -ForegroundColor Cyan
Invoke-NativeGate '  dynamic_video_gpu_source_contract_test.dart' { flutter test test/dynamic_video_gpu_source_contract_test.dart }
Invoke-NativeGate '  realtime_video_overlay_bridge_test.dart' { flutter test test/realtime_video_overlay_bridge_test.dart }
Invoke-NativeGate '  realtime_video_overlay_layout_test.dart' { flutter test test/realtime_video_overlay_layout_test.dart }
Invoke-NativeGate '  video_capture_orientation_test.dart' { flutter test test/video_capture_orientation_test.dart }
Invoke-NativeGate '  video_watermark_processor_test.dart' { flutter test test/video_watermark_processor_test.dart }

Invoke-NativeGate '== Phase 7.2.3: full tests ==' { flutter test }
Invoke-NativeGate '== Phase 7.2.3: Android debug build ==' { flutter build apk --debug }

Write-Host 'Phase 7.2.3 automated gate PASS. Run the physical-device matrix in PHASE_7_2_3_STOCK_CAMERA_HUD_ORIENTATION.md before release.' -ForegroundColor Green
