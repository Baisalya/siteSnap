# SurveyCam Play Console subscription runbook

This setup lets the trial change in Google Play Console without publishing an
app update. The app reads the active `annual199` subscription offer from Google
Play and falls back to any active free-trial offer on that base plan.

## Prepared offers

| Offer ID | Trial | Current status | Intended use |
| --- | --- | --- | --- |
| `launch-1y-free` | 1 year | Active | Current launch offer |
| `launch-2m-free` | 2 months | Draft | Use from February 2027 |
| `standard-7d-trial` | 7 days | Draft | Use from April 2027 onward |

All three offers belong to subscription `surveycam_pro`, yearly base plan
`annual199`, and target new customers who have never had this subscription.

## Switch to the two-month trial on 12 February 2027

1. Open Play Console.
2. Select **SurveyCam - Location & Geo Tag**.
3. Open **Monetize with Play → Products → Subscriptions**.
4. Open **SurveyCam Pro** (`surveycam_pro`).
5. Open `launch-2m-free`, click **Activate**, and confirm.
6. Open `launch-1y-free`, click **Deactivate**, and confirm.
7. Return to the subscription list and verify that `launch-2m-free` is Active
   and `launch-1y-free` is Inactive.

## Switch to the seven-day trial on 12 April 2027

1. Open the same **SurveyCam Pro** subscription page.
2. Open `standard-7d-trial`, click **Activate**, and confirm.
3. Open `launch-2m-free`, click **Deactivate**, and confirm.
4. Verify that `standard-7d-trial` is Active and the other trial offers are
   Inactive.

## Important behavior

- Keep only one free-trial offer active at a time. This makes the offer shown
  by the app deterministic.
- Deactivating an offer affects only new purchases. Anyone who already started
  a one-year or two-month trial keeps the trial terms they accepted.
- Do not deactivate the `annual199` base plan. Only switch its offers.
- Trial activation/deactivation does not require an app update.
- Before a production monetization release, configure the HTTPS purchase
  verification endpoint. Local Play verification is only acceptable for a
  closed/license-testing build.

## Closed-test build flags

Use these only for the closed testing bundle:

```text
--dart-define=SURVEYCAM_FREE_LAUNCH_MODE=false
--dart-define=SURVEYCAM_ALLOW_LOCAL_PLAY_VERIFICATION=true
```

For production, omit the local-verification flag and provide:

```text
--dart-define=SURVEYCAM_FREE_LAUNCH_MODE=false
--dart-define=SURVEYCAM_PURCHASE_VERIFICATION_URL=https://YOUR-HTTPS-ENDPOINT
```

## Closed-test billing checklist

1. In the developer-level Play Console, open **Settings → License testing**.
2. Select the same email lists used by **Closed testing - Alpha** and keep the
   license response set to `RESPOND_NORMALLY`.
3. On an ARM64 Android phone, sign in to Google Play with an account from one
   of those lists.
4. Join the test at
   `https://play.google.com/apps/testing/com.baishalya.surveycam`, then install
   or update SurveyCam from Google Play.
5. Start the Pro checkout and close/back out of the Google Play sheet. Verify
   that the subscription button stops loading and can be tapped again without
   restarting the app.
6. Start checkout again and use Google Play's declining test payment method.
   Verify that an error appears, the button stops loading, and retry works.
7. Also complete one successful test purchase, reopen the app, and verify that
   Pro restores correctly. Cancel the test subscription in Google Play and
   confirm the entitlement refreshes after Play reports the change.

The version 40 Alpha artifact is ARM64-only to keep the browser upload small;
version 39 remains in the same release as a fallback for other device ABIs.
Do not promote this mixed closed-test release to production.
