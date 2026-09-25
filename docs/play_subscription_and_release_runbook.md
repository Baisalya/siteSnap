# SurveyCam Play subscription and update runbook

This document is the production checklist for the subscription and mandatory
update code in the app. The checked-in default remains free-launch mode so a
missing Play Console product or verification service cannot lock out existing
users.

For a shorter, non-technical Play Console checklist, see
[`owner_play_console_guide.md`](owner_play_console_guide.md).

## AI start here: choose one action

If the owner's current request does not already say what to do, ask which of
these three jobs is wanted:

1. QA/testing only.
2. Generate the secure subscription AAB only.
3. Store action only: upload an existing AAB to Closed testing or promote the
   exact tested Closed release to Production.

The AAB command never runs analysis or the test suite, and the QA command never
generates an AAB.
When the owner says the current source has already been tested, build with the
default packaging-only command and record that QA was reused. Run fresh QA only
when explicitly requested, when source/dependency/build configuration changed
after the recorded QA, or when no usable QA evidence exists and the owner
chooses to run it. Upload and promotion reuse the existing artifact and must
never trigger a rebuild.

QA-only commands:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

## Play Console subscription

| Item | Required value | Notes |
|---|---|---|
| Product ID | `surveycam_pro` | Must match `SURVEYCAM_PRO_PRODUCT_ID`. |
| Base plan ID | `annual199` | Auto-renewing, yearly billing, available in every intended country. |
| India base price | ₹199/year | Let Google Play create localized prices, then review them country by country. The numeric amount cannot literally be ₹199 in every currency. |
| Launch offer ID | `launch-1y-free` | Use Play-managed **New customer acquisition** eligibility (not developer-determined), one free phase of one year, followed by the annual base plan. The intended six-month signup campaign ends 11 February 2027; deactivate only this offer then if the campaign is not extended. |
| Grace period/account hold | Enabled | Configure these in Play Console and make the verification service return the current entitlement state. |
| License testers | Owner plus QA accounts | Test accounts must accept the Play testing invitation. |

The app reads the title, trial phase, renewal price, and currency directly from
Google Play. Do not hardcode the displayed worldwide price.

## India rewarded ads

SurveyCam uses an explicit rewarded-ad choice for non-Pro users whose current
GPS country resolves to India. Other countries remain subscription-only. If
country or ad consent cannot be verified, the app fails closed to the Pro
option. Never replace this flow with surprise interstitials on camera launch,
the shutter, or navigation.

For the future app and console changes required to expand rewarded ads beyond
India, see [`all_country_ads_expansion_runbook.md`](all_country_ads_expansion_runbook.md).

| Item | Required value |
|---|---|
| AdMob Android app ID | `ca-app-pub-1529558529658186~9917498367` |
| Rewarded ad unit | `ca-app-pub-1529558529658186/7575240208` |
| Debug ad unit | Google's rewarded test unit, selected automatically in debug builds |

Before Closed testing, complete these console items:

1. In AdMob **Privacy & messaging**, publish the required consent message.
2. In Play Console **App content → Ads**, declare that the app contains ads.
3. Update Play Console **Data safety** for Google Mobile Ads data handling.
4. Test reward earned, early dismissal, no-fill/offline, consent, Pro ad bypass,
   and India/non-India behavior on Play-installed accounts.
5. Once the production Play listing is searchable, link the SurveyCam AdMob app
   to that listing and complete AdMob app readiness review.

## Secure purchase verification

Production subscription builds require an HTTPS endpoint passed as
`SURVEYCAM_PURCHASE_VERIFICATION_URL`. The endpoint must use the Google Play
Developer API on the server; a Play service-account credential must never be
included in the APK/AAB.

Current production verifier:

```text
https://baisalya-entitlement-api.baishalya1999.workers.dev/v1/google-play/verify
```

Request body:

```json
{
  "packageName": "com.baishalya.surveycam",
  "productId": "surveycam_pro",
  "purchaseToken": "token-from-google-play",
  "purchaseId": "optional-order-id"
}
```

Response body:

```json
{
  "valid": true,
  "active": true,
  "expiresAtMs": 1817673600000,
  "message": null
}
```

The server should validate the package, product, purchase state, expiry,
cancellation, grace period, account hold, and token ownership. It should inspect
acknowledgement state but allow a valid new unacknowledged purchase so the app
can acknowledge it immediately after verification.
Rate-limit the endpoint and log only redacted token identifiers. The app grants
Pro only after an active response and caches the result for a maximum seven-day
offline grace period.

## Build modes

| Purpose | Build command/configuration | Result |
|---|---|---|
| Current safe production rollout | Normal `flutter build appbundle --release` | Free-launch mode remains enabled; all prepared Pro features continue working. |
| Internal Play license test only | Add `--dart-define=SURVEYCAM_FREE_LAUNCH_MODE=false --dart-define=SURVEYCAM_ALLOW_LOCAL_PLAY_VERIFICATION=true` | Tests checkout/restore without a backend. Never promote this artifact to production. |
| Secure closed test and production | Run `tool/build_play_subscription_release.ps1` | Pro gates use the deployed verifier and local verification remains disabled. |

Other optional defines are:

```text
SURVEYCAM_PRO_PRODUCT_ID=surveycam_pro
SURVEYCAM_PRO_BASE_PLAN_ID=annual199
SURVEYCAM_PRO_OFFER_ID=launch-1y-free
SURVEYCAM_ADMOB_REWARDED_ID=ca-app-pub-1529558529658186/7575240208
SURVEYCAM_REQUIRED_UPDATE_GAP=2
SURVEYCAM_REQUIRED_UPDATE_PRIORITY=4
SURVEYCAM_REQUIRED_UPDATE_STALENESS_DAYS=14
```

## Generate the paid Play release

Play Console production releases use an Android App Bundle (`.aab`), not a
sideload APK. Increment the `+buildNumber` in `pubspec.yaml`, then run:

```powershell
.\tool\build_play_subscription_release.ps1
```

The command restores dependencies, builds the AAB, and records its size/hash.
It never runs `flutter analyze` or `flutter test`. Run the QA-only commands in
the earlier section as a separate action when fresh QA is requested.

The build command creates:

```text
build/app/outputs/bundle/release/app-release.aab
```

Equivalent command:

```powershell
flutter build appbundle --release `
  --dart-define=SURVEYCAM_FREE_LAUNCH_MODE=false `
  --dart-define=SURVEYCAM_ALLOW_LOCAL_PLAY_VERIFICATION=false `
  --dart-define=SURVEYCAM_PURCHASE_VERIFICATION_URL=https://baisalya-entitlement-api.baishalya1999.workers.dev/v1/google-play/verify `
  --dart-define=SURVEYCAM_PRO_PRODUCT_ID=surveycam_pro `
  --dart-define=SURVEYCAM_PRO_BASE_PLAN_ID=annual199 `
  --dart-define=SURVEYCAM_PRO_OFFER_ID=launch-1y-free `
  --dart-define=SURVEYCAM_PRO_LAUNCH_OFFER_ENDS_AT=2027-02-11T23:59:59+05:30 `
  --dart-define=SURVEYCAM_ADMOB_REWARDED_ID=ca-app-pub-1529558529658186/7575240208
```

Never include the Google service-account JSON or private key in this command,
repository, APK, or AAB. The app bundle contains only the public HTTPS verifier
URL.

## Closed test to production without losing monetization

1. Upload the secure AAB to **Closed testing → Alpha** and send it for review.
2. Install through the closed-test Play link with a license tester.
3. Verify purchase, cancellation, pending payment, restore, reinstall, expiry,
   grace period, an offline/server-error retry, rewarded access, early ad
   dismissal, no-fill, Pro ad bypass, and India/non-India behavior.
4. Keep subscription `surveycam_pro`, base plan `annual199`, and offer
   `launch-1y-free` active.
5. From the tested Alpha release choose **Promote release → Production**. Promote
   the same artifact; do not rebuild it with different defines.
6. Review production countries and rollout, then send the production promotion
   for review. With Managed publishing on, publish after approval.

Promotion preserves the compiled paid configuration. Eligible new customers
see Google Play's one-year free trial at checkout, authorize the ₹0 initial
charge and the future yearly renewal, and are charged automatically by Google
after the trial unless they cancel. Ineligible customers see the Store-provided
paid price. SurveyCam opens checkout when the user selects a locked Pro feature;
it does not force a purchase dialog at app launch.

Production promotion is a Play Console action only. Do not run Flutter tests or
the AAB build script during promotion; use the exact Alpha artifact and its
recorded version/hash.

## Safe rollout order

| Stage | Track/rollout | Required QA and exit condition |
|---|---|---|
| 1. Updater foundation | Release build 35 with free-launch mode; internal, closed, then staged production | Update check never blocks debug, non-Play installs, or offline users. Flexible update downloads and completes. |
| 2. Product setup | Play Console subscription and launch offer | Product and localized prices appear for license testers in every target region. |
| 3. Billing QA | Internal/closed track only | New purchase, pending payment, cancellation, restore after reinstall, multiple devices, offline cache, expiry, grace period, and account hold all pass. |
| 4. Monetization launch | Secure-verification build, 5% then 20%, 50%, 100% | Crash/ANR, checkout failure, verification error, restore failure, refund, and conversion dashboards stay healthy at each gate. |
| 5. Mandatory update | Publish a newer build to all intended users before enforcing it | Confirm Play returns the update on real Play-installed devices. Use update priority 4+ for an immediately required next build, or allow the two-build/14-day safety thresholds to apply. |
| 6. Rollback readiness | Keep the last good AAB and remote verification service backwards compatible | If billing or update metrics regress, halt the staged rollout. Do not disable an already-installed client by taking the verifier offline. |

Mandatory update state cannot be dismissed. If Google's immediate flow is not
allowed, the app opens its Play listing and stays blocked. An initial update
check failure does not lock an offline user; after a required update has been
confirmed in the current session, a retry failure cannot bypass it.

Official references:

- <https://developer.android.com/google/play/billing/integrate.html>
- <https://developer.android.com/google/play/billing/test>
- <https://support.google.com/googleplay/android-developer/answer/12154973>
- <https://developer.android.com/guide/playcore/in-app-updates>
- <https://developer.android.com/guide/playcore/in-app-updates/test>
- <https://support.google.com/googleplay/android-developer/answer/6346149>
