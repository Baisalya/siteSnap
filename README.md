# SurveyCam

SurveyCam is a Flutter mobile app for capturing proof-based photos and videos with GPS, date, time, notes, and watermark overlays. It is built for field surveys, site inspections, work proof, delivery verification, and location-backed documentation.

## Current Position

SurveyCam is planned as a free Play Store launch first. The codebase now includes a lightweight premium-ready structure so future monetization can be added with less rework.

Current mode:

- Free for all users
- Premium features prepared behind a central policy
- No Google Play Billing dependency added yet
- App size kept smaller by avoiding heavy monetization code until needed

## Core Features

- Camera capture with overlay watermark
- Video capture with overlay processing
- GPS latitude, longitude, altitude, and address support
- Date and time watermark
- Weather and sensor-based overlay fields where available
- Basic note and extra note handling
- Saved note history for reusable field notes
- Local gallery for captured media
- Project folders for organizing field captures
- PDF proof report export from selected gallery captures
- Custom PDF report title, project name, and photo-wise descriptions
- Local proof manifest and diagnostics support
- Privacy-focused local storage

## Premium-Ready Features

These features are prepared as future SurveyCam Pro candidates:

- Custom company logo
- Saved note templates
- Project folders
- PDF proof reports
- Custom watermark colors, text, and logo
- Tamper-evident proof IDs and verification

PDF proof reports are implemented for the free launch and remain connected to the premium policy so they can become a Pro feature later. During export, users can choose a report template, edit the report title, enter a project name, and add a separate description for each selected photo.

Premium gates are centralized in:

```text
lib/core/monetization/premium_policy.dart
lib/core/monetization/premium_feature.dart
```

The app currently uses free launch mode. When monetization is added later, connect Google Play Billing entitlement to the premium policy and then disable free launch mode.

## Project Folders

Project folder code lives in:

```text
lib/features/projects/
```

Users can select an active project from the camera or gallery. New captures are assigned to that active project, and the gallery can filter media by project.

## Privacy

SurveyCam is designed around local-first storage. Captures, notes, project assignments, and proof information remain on the device unless the user manually shares or exports them.

## Built With

- Flutter
- Dart
- Camera plugins
- GPS/location services
- Local device storage
- Riverpod state management

## Development

Install dependencies:

```bash
flutter pub get
```

Run static analysis:

```bash
flutter analyze
```

Run tests:

```bash
flutter test
```

## Future Monetization Checklist

When SurveyCam is ready for paid features:

1. Create a product or subscription in Google Play Console.
2. Add a billing package such as `in_app_purchase`.
3. Implement purchase, restore, and entitlement checks.
4. Connect entitlement status to `premiumPolicyProvider`.
5. Change free launch mode to paid-gated mode.
6. Add an Upgrade to Pro screen or dialog.
7. Test with Play Console license testers.
8. Release through internal testing before production.
