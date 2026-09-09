# Fix In-App Purchase Visibility in Testing

The app is currently configured to skip In-App Purchase (IAP) initialization by default through a "Free Launch Mode" flag. This plan enables IAP by default so it appears in Play Store testing tracks.

## Proposed Changes

### Monetization Configuration

#### [premium_config.dart](file:///C:/Users/baish/Downloads/siteSnap/lib/core/monetization/premium_config.dart)

- Change `freeLaunchMode` default value from `true` to `false` to enable billing initialization.
- (Optional but recommended for testing) Change `allowLocalPlayVerification` default to `true` to allow testing without a backend server configured.

```diff
   static const bool freeLaunchMode = bool.fromEnvironment(
     'SURVEYCAM_FREE_LAUNCH_MODE',
-    defaultValue: true,
+    defaultValue: false,
   );

   static const bool allowLocalPlayVerification = bool.fromEnvironment(
     'SURVEYCAM_ALLOW_LOCAL_PLAY_VERIFICATION',
-    defaultValue: false,
+    defaultValue: true,
   );
```

## Verification Plan

### Automated Tests
- Run `flutter test` to ensure monetization logic still passes.
- Specifically check `test/core/services/pdf_proof_report_service_test.dart` if it mocks premium state.

### Manual Verification
- Verify that `premiumPolicyProvider` now initializes the `billingControllerProvider` instead of returning a static "free" policy.
- Check `ProUpgradeScreen` (by navigating to it in the app) to see if it now shows "Loading Google Play price..." instead of just saying Pro is included.
