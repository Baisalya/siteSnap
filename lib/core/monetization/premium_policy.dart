import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'billing_controller.dart';
import 'premium_feature.dart';
import 'premium_config.dart';

class PremiumPolicy {
  const PremiumPolicy({
    this.freeLaunchMode = true,
    this.userHasProPurchase = false,
  });

  final bool freeLaunchMode;
  final bool userHasProPurchase;

  bool canUse(PremiumFeature feature) {
    if (freeLaunchMode) return true;
    return userHasProPurchase;
  }
}

final premiumPolicyProvider = Provider<PremiumPolicy>((ref) {
  if (PremiumConfig.freeLaunchMode) {
    // Avoid starting the billing client during the free launch. This keeps the
    // camera startup path small until monetization is deliberately enabled.
    return const PremiumPolicy(freeLaunchMode: true);
  }
  final billing = ref.watch(billingControllerProvider);
  return PremiumPolicy(
    freeLaunchMode: PremiumConfig.freeLaunchMode,
    userHasProPurchase: billing.isPro,
  );
});
