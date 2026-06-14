import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'premium_feature.dart';

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
  return const PremiumPolicy();
});
