# SurveyCam Agent Notes

## Product Direction

SurveyCam is a GPS/time/photo proof camera app for field work. The current Play Store plan is free launch first, with premium features prepared in code so monetization can be enabled later without a large rewrite.

## Current Premium Strategy

- Keep the app free for now.
- Premium-ready features should be gated through `PremiumPolicy`.
- Do not add Google Play Billing until the owner is ready to monetize.
- When monetization starts, connect purchase/subscription status to:

```text
lib/core/monetization/premium_policy.dart
```

Set `freeLaunchMode` to `false` only after billing restore/purchase checks are implemented and tested.

## Premium Feature Candidates

The current premium feature enum is in:

```text
lib/core/monetization/premium_feature.dart
```

Prepared Pro feature buckets:

- Project folders
- PDF proof reports, currently implemented and free during launch
- Custom company branding/logo/colors
- Saved note templates
- Proof verification/tamper-evident IDs

## Project Folder Implementation

Project folder code lives under:

```text
lib/features/projects/
```

Storage is lightweight and uses `SharedPreferences`:

```text
lib/features/projects/data/project_storage.dart
```

The active project is selected from the camera/gallery UI. Captures are assigned by normalized file path, and the gallery filters files by the active project.

## Save Flow Notes

Project assignment is wired into image/video processing jobs:

```text
lib/core/services/image_processing_job.dart
lib/core/services/video_processing_job.dart
lib/core/services/background_video_task.dart
lib/features/overlay/presentation/overlay_viewmodel.dart
lib/features/camera/presentation/camera_viewmodel.dart
```

If save paths change in future, make sure project assignment follows the final saved file path, not only the temporary capture path.

## PDF Proof Reports

PDF report generation lives in:

```text
lib/core/services/pdf_proof_report_service.dart
```

The gallery selection toolbar exposes PDF export. It supports standard and compact report templates, lets the user edit the report title/project name, collects a separate description for each selected capture, embeds selected photo previews, includes file details, and adds a report proof ID derived from selected file hashes.

The feature is currently available because `freeLaunchMode` is true, but it is checked through `PremiumFeature.pdfReports` so it can be moved behind Pro later.

## Monetization Checklist For Later

1. Create in-app product or subscription in Google Play Console.
2. Add a billing package such as `in_app_purchase`.
3. Implement a small billing service that can query, buy, and restore Pro entitlement.
4. Feed entitlement into `premiumPolicyProvider`.
5. Change `freeLaunchMode` to `false`.
6. Add an Upgrade to Pro screen or dialog for locked features.
7. Test with Play Console license testers.
8. Release through internal testing before production.

## Testing Expectations

Before finishing any future change, run:

```text
flutter analyze
flutter test
```

Existing relevant tests:

```text
test/core/services/pdf_proof_report_service_test.dart
test/project_provider_test.dart
test/saved_notes_provider_test.dart
test/gallery_repository_test.dart
```

Add focused tests when changing project assignment, premium gates, gallery filtering, proof IDs, or save processing.

## Implementation Preferences

- Keep app size small.
- Prefer lightweight local storage unless cloud sync is explicitly requested.
- Avoid adding heavy SDKs until needed.
- Keep premium gates centralized instead of scattering hardcoded purchase checks.
- Preserve the free launch behavior unless the owner explicitly asks to enable monetization.
