SiteSnap Phase 7.2 — Single-Stream Dynamic Rotation GPU Compositor

Base: Phase 7.1.5 Photo/Preview Isolation + Recording Orientation Lock.

Apply these files over that baseline only. PHOTO/global preview orientation files are intentionally not part of this modified-files ZIP because they remain byte-identical to the known-good Phase 7.1.5 baseline.

Validation on Windows:
  powershell -ExecutionPolicy Bypass -File .\tool\phase7_2_release_gate.ps1

Then run the physical-device matrix in:
  PHASE_7_2_SINGLE_STREAM_DYNAMIC_ROTATION_GPU_COMPOSITOR.md
