# Phase 8.0.1 — Location Bootstrap Test Lifecycle Hotfix

## Why this hotfix exists

The Phase 8 Windows release gate passed `flutter analyze` and the professional-photo, camera serialization, interaction, and location-policy focused tests. It then failed only in `test/location_stream_bootstrap_test.dart`.

The failure was a Riverpod lifecycle mismatch in the test harness:

`locationStreamProvider` is intentionally `StreamProvider.autoDispose`. Production observes it with `ref.listen(...)` from the camera screen, so the provider has a live listener while its asynchronous service/permission/cache bootstrap runs. The test used only `container.read(locationStreamProvider.future)`. A bare read of an auto-dispose provider does not retain an external listener, so Riverpod could dispose the provider while it was still in the loading state and before the first `LocationFix` was emitted.

This produced:

`Bad state: The provider StreamProvider<LocationFix> was disposed during loading state, yet no value could be emitted.`

## Fix

The focused bootstrap test now keeps a real `ProviderContainer.listen(...)` subscription alive while awaiting `locationStreamProvider.future`, then closes that subscription after the first value is received.

This matches the production camera lifecycle and tests the intended first-event behavior without weakening `autoDispose`.

## Runtime impact

None.

No production Dart, CameraX, photo, video, overlay, subscription, billing, zoom, focus, thermal, or location implementation file is changed by Phase 8.0.1.

In particular, `locationStreamProvider` remains `autoDispose`; background GPS suspension and the Phase 8 thermal policy are preserved.

## Expected Windows gate behavior

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\phase8_release_gate.ps1
```

Expected sequence:

1. `flutter analyze` — No issues found.
2. `professional_photo_source_contract_test.dart` — pass.
3. `camera_repository_serialization_test.dart` — pass.
4. `camera_interaction_utils_test.dart` — pass.
5. `location_fix_policy_test.dart` — pass.
6. `location_stream_bootstrap_test.dart` — both bootstrap tests pass.
7. Remaining video regression tests, full test suite, and Android debug build continue only if every prior command exits zero.

## Changed runtime behavior

None. This is a certification/test-lifecycle hotfix only.
