# SurveyCam all-country rewarded ads expansion runbook

This runbook explains how to expand SurveyCam's optional rewarded ads beyond
India in a future release without changing the subscription experience.

## Current production behavior

- Rewarded ads are available only when a non-Pro user's recent GPS location
  resolves to India.
- Users outside India, or users whose country cannot be verified, remain
  subscription-only.
- SurveyCam Pro works in every Play country where the subscription base plan is
  available and removes rewarded ads.
- The European regulations message is published for the EEA, United Kingdom,
  and Switzerland through Google User Messaging Platform (UMP).
- The app fails closed: if country, consent, ad inventory, or the verification
  service is unavailable, it does not grant an ad-based unlock.

Relevant implementation files:

```text
lib/core/monetization/monetization_market.dart
lib/core/monetization/premium_access_gate.dart
lib/core/monetization/rewarded_ad_service.dart
lib/privacypolicy/PrivacyDialog.dart
```

## Important distinction: consent targeting versus ad availability

Changing AdMob **Privacy & messaging → European regulations → Targeting** to
`Everywhere` changes where that GDPR-style consent message may appear. It does
not bypass SurveyCam's India-only rewarded-ad check.

Actual all-country rewarded-ad availability requires an app update because the
current market gate is compiled into `premium_access_gate.dart`.

The recommended consent setup for a worldwide launch is:

1. Keep the European regulations message enabled for the EEA, UK, and
   Switzerland.
2. Configure the applicable US state regulations message before enabling US
   ad traffic.
3. Add any other region-specific messages required by Google or local law.
4. Use `Everywhere` for the European message only if the owner intentionally
   wants the GDPR-style choice shown globally.
5. Keep UMP in the request path and never request an ad when
   `ConsentInformation.canRequestAds()` is false.

## One-time app release required for worldwide ads

1. Replace the India-only condition in
   `lib/core/monetization/premium_access_gate.dart` with an explicit supported
   market policy.
2. Continue treating `MonetizationMarket.unknown` as ineligible so location or
   country-resolution failures remain fail-closed.
3. Update India-specific user-facing text in the premium gate and
   `lib/privacypolicy/PrivacyDialog.dart`.
4. Update `https://baisalya.com/surveycam/privacy.html` so it no longer says
   rewarded access is limited to India.
5. Confirm the AdMob app and rewarded unit are approved and able to serve in
   every intended country.
6. Confirm the Play subscription base plan remains active in those countries;
   Pro must stay available as the ad-free option.
7. Run `flutter analyze`, `flutter test`, and build a new secure AAB with
   `tool/build_play_subscription_release.ps1 -RunQualityChecks`.
8. Upload the AAB to Closed testing and test it using Play-installed accounts
   in representative regions before promoting that exact artifact.

Do not use Google Play Billing's country API for advertising decisions. Keep
the existing GPS-derived country approach or replace it with another
advertising-appropriate country signal reviewed for policy and privacy.

## Recommended design for future changes without another app update

The current build has no remote country allowlist. If the owner wants later
country expansion without publishing another AAB, first ship one app version
that reads a server-controlled rewarded-ad market policy.

Recommended policy shape:

```json
{
  "rewardedAdsEnabled": true,
  "allowedCountryCodes": ["IN"],
  "policyVersion": 1
}
```

Use ISO 3166-1 alpha-2 country codes. A future global switch may use an explicit
`allVerifiedCountries` flag rather than a magic `"*"` value.

Safety requirements for the remote policy:

- Ship with a compiled India-only default.
- Cache the last verified policy for a short bounded period.
- If the policy cannot be fetched or parsed, fall back to the compiled default.
- Never allow `unknown` country to become ad-eligible.
- Keep Pro entitlement and purchase restoration independent of the ad policy.
- Version and log policy changes without logging precise location or purchase
  tokens.

After that foundation release is installed, expanding countries can be done by
updating the server allowlist, completing the relevant consent configuration,
and updating the public privacy policy. No app update is then required unless
the SDK, consent flow, or product behavior changes.

## Closed-test checklist for worldwide ads

Test at least one account/device in India, an EEA country, the UK, the US, and a
non-regulated comparison market:

- Non-Pro user sees the rewarded-ad choice only in enabled countries.
- EEA/UK users receive the published UMP choices before an ad request.
- Declining consent does not request an ad and leaves the Pro option available.
- Completing the rewarded ad grants only the intended feature/session access.
- Early dismissal grants nothing.
- Offline, no-fill, consent error, and unknown-country paths fail closed.
- Pro purchase and restore bypass all rewarded ads in every country.
- Subscription checkout shows Play-provided localized pricing and eligibility.
- Captured photos, videos, notes, and reports are never supplied to AdMob.

## Rollout order

1. Complete console consent and privacy changes.
2. Release the country-policy app update to Closed testing.
3. Verify ads and subscriptions together.
4. Promote the exact tested AAB to Production; do not rebuild it.
5. Use staged rollout and monitor crash, ANR, ad-show, consent, checkout,
   verification, restoration, and conversion metrics.
6. Pause expansion or remove countries from the remote allowlist if metrics or
   policy compliance regress.

