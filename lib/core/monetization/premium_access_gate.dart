import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'monetization_market.dart';
import 'premium_feature.dart';
import 'premium_policy.dart';
import 'pro_upgrade_screen.dart';
import 'rewarded_capture_access.dart';
import 'rewarded_ad_service.dart';
import 'rewarded_feature_access.dart';

enum _PremiumAccessChoice { watchAd, getPro }

Future<bool> requestPremiumFeatureAccess({
  required BuildContext context,
  required WidgetRef ref,
  required PremiumFeature feature,
}) async {
  final policy = ref.read(premiumPolicyProvider);
  if (policy.canUse(feature)) return true;

  if (photoRewardFeatures.contains(feature) &&
      ref.read(rewardedCaptureAccessProvider).isFeaturePending(feature)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Your previous premium capture is still saving. Try again when it finishes.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return false;
  }

  // Re-check on every locked entry so a prior permission/service failure does
  // not permanently hide rewarded access for the rest of the session.
  ref.invalidate(monetizationMarketProvider);
  final market = await ref.read(monetizationMarketProvider.future);
  if (!context.mounted) return false;
  if (market != MonetizationMarket.india) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          market == MonetizationMarket.unknown
              ? 'Rewarded access is available only when your location confirms India.'
              : 'In your region, ${feature.accessLabel} requires SurveyCam Pro.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await showProUpgrade(context);
    return false;
  }

  final choice = await showModalBottomSheet<_PremiumAccessChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _PremiumAccessSheet(feature: feature),
  );
  if (!context.mounted || choice == null) return false;
  if (choice == _PremiumAccessChoice.getPro) {
    await showProUpgrade(context);
    return false;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Preparing your rewarded ad…'),
      duration: Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ),
  );
  final outcome = await ref.read(rewardedAdServiceProvider).show();
  if (!context.mounted) return false;
  switch (outcome) {
    case RewardedAdOutcome.earned:
      grantRewardedFeature(ref, feature);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            photoRewardFeatures.contains(feature)
                ? '${feature.accessLabel} unlocked for one capture.'
                : '${feature.accessLabel} unlocked for one use.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return true;
    case RewardedAdOutcome.dismissed:
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Finish the ad to unlock this feature.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    case RewardedAdOutcome.unavailable:
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No ad is available right now. Try again shortly or get Pro.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
  }
}

class _PremiumAccessSheet extends StatelessWidget {
  const _PremiumAccessSheet({required this.feature});

  final PremiumFeature feature;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Material(
          color: const Color(0xFF171717),
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.workspace_premium_rounded,
                  color: Colors.amberAccent,
                  size: 38,
                ),
                const SizedBox(height: 12),
                Text(
                  'Unlock ${feature.accessLabel}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  photoRewardFeatures.contains(feature)
                      ? 'Watch one rewarded ad to use this feature for one photo or video. Saving or sharing that capture ends the unlock. Get Pro for unlimited ad-free access.'
                      : 'Watch one rewarded ad for one use of this feature, or get Pro for unlimited ad-free access.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      _PremiumAccessChoice.watchAd,
                    ),
                    icon: const Icon(Icons.ondemand_video_rounded),
                    label: const Text('Watch ad & continue'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.amberAccent,
                      foregroundColor: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      _PremiumAccessChoice.getPro,
                    ),
                    icon: const Icon(Icons.block_rounded),
                    label: const Text('Get Pro — remove all ads'),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Not now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
