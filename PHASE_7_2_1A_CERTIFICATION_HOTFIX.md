# Phase 7.2.1a — Certification Gate Hotfix

## Why this hotfix exists

The Windows Phase 7.2.1 run exposed two certification defects after the runtime
orientation bridge tests had passed:

1. `realtime_video_overlay_layout_test.dart` treated the complete opposite half
   of the top strip as required to be perfectly transparent. `SurveyCam` uses
   anti-aliased bold text plus a blur shadow, so a few legitimate pixels can
   cross the half-frame test boundary without the branding anchor being wrong.
2. PowerShell `$ErrorActionPreference = 'Stop'` does not automatically turn a
   non-zero exit code from every native executable into a terminating error.
   The old gate therefore continued to the APK build and printed a completion
   message even after a Flutter test had failed.

The Windows analyzer also reported three `unnecessary_import` infos for
`dart:typed_data`.

## What changed

- The runtime VIDEO compositor/placement implementation is intentionally
  unchanged.
- The branding raster test now verifies the actual contract:
  - visible branding mass is on the same horizontal side as the information
    card;
  - the selected extreme edge contains branding;
  - the far opposite edge remains empty.
  This tolerates legitimate glyph anti-aliasing/shadow spread near the center.
- Removed the three unnecessary `dart:typed_data` imports reported by
  `flutter analyze`.
- Replaced the release runner with a fail-fast `Invoke-NativeGate` wrapper that
  checks `$LASTEXITCODE` after every Dart/Flutter command.

## Runtime scope

No CameraX, GPU shader, recorder, PHOTO, preview, ImageCapture, overlay-layout,
or watermark placement production code is changed by 7.2.1a. It is a
certification/test-runner hotfix on top of Phase 7.2.1.

## Re-run

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\phase7_2_1_release_gate.ps1
```

Expected result:

- `flutter analyze` reports **No issues found!**
- all four focused suites pass;
- full `flutter test` passes;
- debug APK builds;
- only then the script prints `Phase 7.2.1a automated gate PASS`.

After that, continue with the physical-device matrix from
`PHASE_7_2_1_ATOMIC_ORIENTATION_LAYOUT_COMMIT.md`.
