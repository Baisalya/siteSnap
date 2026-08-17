# SurveyCam owner guide: subscriptions and releases

Use this checklist when a non-technical owner needs to manage SurveyCam in
Google Play Console. Never upload an AAB unless the developer has labelled it
for the exact track you are using.

## Current subscription setup

| Setting | Current value | Owner action |
|---|---|---|
| Subscription product | `surveycam_pro` | Keep this ID. Product IDs cannot be safely renamed in the app. |
| Paid base plan | `annual199` | Active, yearly, India price ₹199/year. |
| Launch offer | `launch-1y-free` | Active, new customers only, one-year free trial, then the yearly price. |
| Old incorrect plan | `annual-199` | Inactive. Do not reactivate it; it was monthly. |
| Six-month joining window | 11 Aug 2026 to 11 Feb 2027 | On 11 Feb 2027, deactivate only `launch-1y-free` if the campaign should end. Do not deactivate `annual199`. Existing subscribers keep the terms Play already granted them. |

The offer is **one free year for customers who join during the six-month
campaign**. Google Play does not make every country literally ₹199; it creates
local-currency prices that must be reviewed in the base plan.

## Change the subscription later

| Goal | Play Console path | Safe action | Never do |
|---|---|---|---|
| Change yearly price | Monetize with Play → Products → Subscriptions → `surveycam_pro` → `annual199` | Edit regional prices, review the existing-subscriber choice shown by Play, save, then activate the change. | Do not create another "annual" plan just to change a price. |
| End the free campaign | `surveycam_pro` → `annual199` → Offers → `launch-1y-free` | Deactivate the offer. The paid yearly base plan stays active. | Do not deactivate the subscription or `annual199`. |
| Run a different promotion | `annual199` → Add offer | Create a new uniquely named offer, set Play-managed eligibility and its phases, save, review, activate, then ask the developer to update the app only if the offer ID changed. | Do not reuse an ID for a different promise. |
| Pause all new Pro sales | `surveycam_pro` details | Ask the developer first. Existing purchasers, restores, and app gates must be handled before deactivation. | Do not delete products or remove entitlement checks. |

After any price or offer change, test checkout with a Play license tester. The
checkout sheet is the source of truth for trial length, renewal price, tax, and
currency.

## Release a new app version

| Step | Owner action in Play Console | Check before continuing |
|---|---|---|
| 1. Receive build | Get the AAB, version name/code, SHA-256, intended track, and release notes from the developer. | The developer says `flutter analyze` and all tests passed. |
| 2. Internal test | Test and release → Testing → Internal testing → Create new release → Upload AAB. | Play shows the expected new version code and no blocking error. |
| 3. Keep testers | Open the **Testers** tab and select the existing tester list. Copy the opt-in link. | Do not delete or replace tester email lists. |
| 4. Device QA | Install/update only from the Play opt-in link on a real Android phone. | Complete the camera and billing checklist below. |
| 5. Closed test | Promote the proven build to Closed testing if wider QA is needed. | No new crash/ANR, save, billing, or restore regression. |
| 6. Production | Create/promote the release to Production and use a staged rollout: 5% → 20% → 50% → 100%. | Check Android vitals and user reports for at least 24–48 hours at each gate. Stop rollout if metrics worsen. |

### Real-device QA checklist

| Area | Pass condition |
|---|---|
| First photo | After the preview says ready, the first shutter responds promptly and opens the preview without freezing. |
| Repeated photos | Take 10 photos quickly; no double capture, black preview, crash, or stuck spinner. |
| Zoom | Pinch slowly and quickly; zoom is smooth and bounded. Tap the visible `x` chip to animate back to 1.0x. |
| Focus/exposure | Tap to focus and drag vertically with one finger; controls do not fight pinch zoom. |
| Video | Record for at least 30 seconds; the red timer advances accurately and the saved video plays fully. |
| Video lifecycle | Test flash, front/back camera, background/resume, and stopping soon after start. No lost recording or crash. |
| Proof output | Confirm watermark, GPS/time, selected project, gallery, PDF report, logo, and saved note templates. |
| Subscription | New eligible tester sees one free year then the localized yearly price; purchase, restore after reinstall, cancel, pending, offline, and expiry behavior match the plan. |

## Mandatory update in plain language

SurveyCam already contains an update gate. A normal next build is optional. A
user two or more version codes behind, or an update known by Play for 14 days,
becomes mandatory. A Play update priority of 4 or 5 can also make the update
mandatory, but that priority must be prepared by the release developer/API
workflow; do not assume the Play Console page set it.

Before relying on a mandatory update:

1. Publish the replacement build to every intended country and reach 100%.
2. Install the old Play version on a real phone.
3. Confirm Play offers the new version.
4. Confirm offline startup is not blocked before Play has established that an
   update is required.
5. Keep the previous good AAB and do not remove backend compatibility.

## Important build labels

| Label from developer | Allowed destination |
|---|---|
| `INTERNAL SUBSCRIPTION QA` | Internal/closed testing only. Never production; it uses local Play verification. |
| `FREE-LAUNCH PRODUCTION` | Production-safe while all prepared features remain free. |
| `SECURE SUBSCRIPTION PRODUCTION` | Production only after the purchase-verification server is live and restore/cancel/refund tests pass. |

No release can guarantee a 0% crash or ANR rate. The safe goal is zero known
blocking defects, passing tests, real-device QA, and a staged rollout with a
clear stop/rollback decision.
