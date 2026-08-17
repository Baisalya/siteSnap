class PremiumConfig {
  const PremiumConfig._();

  /// Keep this true for production until Play Console products, restore,
  /// verification, and closed-track testing have all passed.
  static const bool freeLaunchMode = bool.fromEnvironment(
    'SURVEYCAM_FREE_LAUNCH_MODE',
    defaultValue: true,
  );

  static const String proProductId = String.fromEnvironment(
    'SURVEYCAM_PRO_PRODUCT_ID',
    defaultValue: 'surveycam_pro',
  );

  static const String annualBasePlanId = String.fromEnvironment(
    'SURVEYCAM_PRO_BASE_PLAN_ID',
    defaultValue: 'annual199',
  );

  static const String launchOfferId = String.fromEnvironment(
    'SURVEYCAM_PRO_OFFER_ID',
    defaultValue: 'launch-1y-free',
  );

  /// Marketing window for the launch offer. Google Play remains the source of
  /// truth for offer eligibility and checkout pricing; this value only powers
  /// the honest countdown shown on the Pro screen.
  static const String launchOfferEndsAtIso = String.fromEnvironment(
    'SURVEYCAM_PRO_LAUNCH_OFFER_ENDS_AT',
    defaultValue: '2027-02-11T23:59:59+05:30',
  );

  static DateTime? get launchOfferEndsAt =>
      DateTime.tryParse(launchOfferEndsAtIso);

  /// HTTPS endpoint that verifies Google Play purchase tokens using the Play
  /// Developer API. Expected response:
  /// {"valid":true,"active":true,"expiresAtMs":1234567890000}
  static const String verificationUrl = String.fromEnvironment(
    'SURVEYCAM_PURCHASE_VERIFICATION_URL',
  );

  /// Only for Play license-testing builds. Never enable this on production.
  static const bool allowLocalPlayVerification = bool.fromEnvironment(
    'SURVEYCAM_ALLOW_LOCAL_PLAY_VERIFICATION',
    defaultValue: false,
  );

  static const Duration offlineEntitlementGrace = Duration(days: 7);
}
