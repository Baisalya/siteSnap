# Phase 7.2.3a — Certification Lint Hotfix

This hotfix is intentionally non-runtime.

## What the Windows gate found

`flutter analyze` stopped on:

`test/realtime_video_overlay_bridge_test.dart:834:15 - curly_braces_in_flow_control_structures`

The Phase 7.2.3 fail-fast PowerShell gate behaved correctly by stopping before tests/build could be certified.

## Fix

All remaining single-line `if` guards in this focused bridge test are now block-bodied statements, including the analyzer-reported completion guard. This satisfies the repository lint without changing the test's behavior.

No production Dart, CameraX, GPU compositor, PHOTO, preview, overlay positioning, recording, or dependency code is changed by 7.2.3a.

## Re-run

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\phase7_2_3_release_gate.ps1
```

Expected order: format -> analyze -> focused tests -> full tests -> Android debug build. The script must stop immediately on any non-zero command.
