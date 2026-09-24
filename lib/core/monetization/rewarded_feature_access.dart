import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'premium_feature.dart';

/// Rewarded unlocks intentionally live only for the current app process.
/// A Pro purchase remains the only persistent, ad-free entitlement.
final rewardedFeatureAccessProvider =
    StateProvider<Set<PremiumFeature>>((ref) => <PremiumFeature>{});

void grantRewardedFeature(WidgetRef ref, PremiumFeature feature) {
  final current = ref.read(rewardedFeatureAccessProvider);
  ref.read(rewardedFeatureAccessProvider.notifier).state = {
    ...current,
    feature,
  };
}

void consumeRewardedFeature(WidgetRef ref, PremiumFeature feature) {
  final current = ref.read(rewardedFeatureAccessProvider);
  if (!current.contains(feature)) return;
  ref.read(rewardedFeatureAccessProvider.notifier).state = {
    for (final item in current)
      if (item != feature) item,
  };
}
