# SurveyCam Play subscription and update runbook

This document is the production checklist for the subscription and mandatory
update code in the app. The checked-in default remains free-launch mode so a
missing Play Console product or verification service cannot lock out existing
users.

For a shorter, non-technical Play Console checklist, see
[`owner_play_console_guide.md`](owner_play_console_guide.md).

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

## Secure purchase verification

Production subscription builds require an HTTPS endpoint passed as
`SURVEYCAM_PURCHASE_VERIFICATION_URL`. The endpoint must use the Google Play
Developer API on the server; a Play service-account credential must never be
included in the APK/AAB.

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
| Secure production subscription | Add `--dart-define=SURVEYCAM_FREE_LAUNCH_MODE=false --dart-define=SURVEYCAM_PURCHASE_VERIFICATION_URL=https://your-domain.example/play/verify` | Pro gates use verified Google Play entitlement. |

Other optional defines are:

```text
SURVEYCAM_PRO_PRODUCT_ID=surveycam_pro
SURVEYCAM_PRO_BASE_PLAN_ID=annual199
SURVEYCAM_PRO_OFFER_ID=launch-1y-free
SURVEYCAM_REQUIRED_UPDATE_GAP=2
SURVEYCAM_REQUIRED_UPDATE_PRIORITY=4
SURVEYCAM_REQUIRED_UPDATE_STALENESS_DAYS=14
```

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
