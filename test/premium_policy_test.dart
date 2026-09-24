import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/core/monetization/monetization_market.dart';
import 'package:surveycam/core/monetization/premium_feature.dart';
import 'package:surveycam/core/monetization/premium_policy.dart';

void main() {
  group('PremiumPolicy', () {
    test('free launch and Pro unlock every feature', () {
      const freeLaunch = PremiumPolicy(freeLaunchMode: true);
      const pro = PremiumPolicy(
        freeLaunchMode: false,
        userHasProPurchase: true,
      );

      for (final feature in PremiumFeature.values) {
        expect(freeLaunch.canUse(feature), isTrue);
        expect(pro.canUse(feature), isTrue);
      }
    });

    test('reward unlock is limited to the granted feature', () {
      const policy = PremiumPolicy(
        freeLaunchMode: false,
        rewardedFeatures: {PremiumFeature.pdfReports},
      );

      expect(policy.canUse(PremiumFeature.pdfReports), isTrue);
      expect(policy.canUse(PremiumFeature.projectFolders), isFalse);
    });
  });

  group('MonetizationMarket', () {
    test('recognizes India case-insensitively', () {
      expect(
        MonetizationMarket.fromCountryCode(' in '),
        MonetizationMarket.india,
      );
    });

    test('fails closed when country is unavailable', () {
      expect(
        MonetizationMarket.fromCountryCode(null),
        MonetizationMarket.unknown,
      );
      expect(
        MonetizationMarket.fromCountryCode(''),
        MonetizationMarket.unknown,
      );
    });

    test('classifies non-India countries separately', () {
      expect(
        MonetizationMarket.fromCountryCode('US'),
        MonetizationMarket.other,
      );
    });
  });
}
