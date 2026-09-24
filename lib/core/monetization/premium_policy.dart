import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'billing_controller.dart';
import 'premium_feature.dart';
import 'premium_config.dart';
import 'rewarded_feature_access.dart';

class PremiumPolicy {
  const PremiumPolicy({
    this.freeLaunchMode = true,
    this.userHasProPurchase = false,
    this.rewardedFeatures = const <PremiumFeature>{},
  });

  final bool freeLaunchMode;
  final bool userHasProPurchase;
  final Set<PremiumFeature> rewardedFeatures;

  bool get isPro => userHasProPurchase;

  bool canUse(PremiumFeature feature) {
    if (freeLaunchMode) return true;
    return userHasProPurchase || rewardedFeatures.contains(feature);
  }
}

final premiumPolicyProvider = Provider<PremiumPolicy>((ref) {
  if (PremiumConfig.freeLaunchMode) {
    // Avoid starting the billing client during the free launch. This keeps the
    // camera startup path small until monetization is deliberately enabled.
    return const PremiumPolicy(freeLaunchMode: true);
  }
  final billing = ref.watch(billingControllerProvider);
  final rewardedFeatures = ref.watch(rewardedFeatureAccessProvider);
  return PremiumPolicy(
    freeLaunchMode: PremiumConfig.freeLaunchMode,
    userHasProPurchase: billing.isPro,
    rewardedFeatures: rewardedFeatures,
  );
});
