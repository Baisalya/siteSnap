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

Invoke-NativeGate '== Phase 7.2.2: format ==' { dart format lib test }
Invoke-NativeGate '== Phase 7.2.2: analyze ==' { flutter analyze }

Write-Host '== Phase 7.2.2: focused rotation/FOV/overlay tests ==' -ForegroundColor Cyan
Invoke-NativeGate '  dynamic_video_gpu_source_contract_test.dart' { flutter test test/dynamic_video_gpu_source_contract_test.dart }
Invoke-NativeGate '  realtime_video_overlay_bridge_test.dart' { flutter test test/realtime_video_overlay_bridge_test.dart }
Invoke-NativeGate '  realtime_video_overlay_layout_test.dart' { flutter test test/realtime_video_overlay_layout_test.dart }
Invoke-NativeGate '  video_capture_orientation_test.dart' { flutter test test/video_capture_orientation_test.dart }
Invoke-NativeGate '  video_watermark_processor_test.dart' { flutter test test/video_watermark_processor_test.dart }

Invoke-NativeGate '== Phase 7.2.2: full tests ==' { flutter test }
Invoke-NativeGate '== Phase 7.2.2: Android debug build ==' { flutter build apk --debug }

Write-Host 'Phase 7.2.2 automated gate PASS. Run the physical-device rotation matrix in PHASE_7_2_2_LIVE_OVERLAY_FIT_CENTER.md before release.' -ForegroundColor Green
