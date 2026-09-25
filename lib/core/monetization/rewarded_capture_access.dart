import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:surveycam/features/overlay/presentation/overlay_settings_provider.dart';
import 'package:surveycam/features/projects/presentation/project_provider.dart';

import 'premium_feature.dart';
import 'premium_policy.dart';
import 'rewarded_feature_access.dart';

const photoRewardFeatures = <PremiumFeature>{
  PremiumFeature.projectFolders,
  PremiumFeature.customBranding,
  PremiumFeature.overlayColors,
};

final rewardedCaptureAccessProvider = Provider<RewardedCaptureAccess>((ref) {
  return RewardedCaptureAccess(ref);
});

/// Keeps photo rewards one-use, including photos saved by the background worker.
/// The worker gets its own immutable project/settings snapshot before a reward
/// is reserved, so a second capture cannot borrow the same rewarded ad.
class RewardedCaptureAccess {
  RewardedCaptureAccess(this._ref);

  final Ref _ref;
  final Map<String, Set<PremiumFeature>> _pendingOutputs = {};

  bool get hasAvailablePhotoRewards => _availablePhotoRewards.isNotEmpty;

  bool isFeaturePending(PremiumFeature feature) =>
      _pendingOutputs.values.any((features) => features.contains(feature));

  Set<PremiumFeature> get _availablePhotoRewards {
    if (_ref.read(premiumPolicyProvider).isPro) return const {};
    return _ref.read(rewardedFeatureAccessProvider).intersection(
          photoRewardFeatures,
        );
  }

  void reserveBackgroundImage(String originalPath) {
    _reserve('image:$originalPath');
  }

  Future<void> completeBackgroundImage(String originalPath) async {
    await _complete('image:$originalPath');
  }

  void failBackgroundImage(String originalPath) {
    _fail('image:$originalPath');
  }

  void reserveVideo(String jobId) => _reserve('video:$jobId');

  Future<void> completeVideo(String jobId) => _complete('video:$jobId');

  void failVideo(String jobId) => _fail('video:$jobId');

  void _reserve(String outputKey) {
    final features = _availablePhotoRewards;
    if (features.isEmpty) return;
    _pendingOutputs[outputKey] = features;
    _removeRewards(features);
  }

  Future<void> _complete(String outputKey) async {
    final features = _pendingOutputs.remove(outputKey);
    if (features != null) await _resetSelections(features);
  }

  void _fail(String outputKey) {
    final features = _pendingOutputs.remove(outputKey);
    if (features == null || _ref.read(premiumPolicyProvider).isPro) return;
    _ref.read(rewardedFeatureAccessProvider.notifier).state = {
      ..._ref.read(rewardedFeatureAccessProvider),
      ...features,
    };
  }

  Future<void> consumeSuccessfulPhoto() async {
    final features = _availablePhotoRewards;
    if (features.isEmpty) return;
    _removeRewards(features);
    await _resetSelections(features);
  }

  void _removeRewards(Set<PremiumFeature> features) {
    _ref.read(rewardedFeatureAccessProvider.notifier).state = {
      for (final feature in _ref.read(rewardedFeatureAccessProvider))
        if (!features.contains(feature)) feature,
    };
  }

  Future<void> _resetSelections(Set<PremiumFeature> features) async {
    if (_ref.read(premiumPolicyProvider).isPro) return;
    // Reset independently: a storage error must not reinstate an already-used
    // reward or prevent the other feature from returning to its free default.
    if (features.contains(PremiumFeature.projectFolders)) {
      try {
        await _ref.read(projectProvider.notifier).setActiveProject(null);
      } catch (error) {
        debugPrint('Could not persist default project: $error');
      }
    }
    if (features.contains(PremiumFeature.customBranding) ||
        features.contains(PremiumFeature.overlayColors)) {
      try {
        await _ref
            .read(overlaySettingsProvider.notifier)
            .resetRewardedSelections(
              branding: features.contains(PremiumFeature.customBranding),
              colors: features.contains(PremiumFeature.overlayColors),
            );
      } catch (error) {
        debugPrint('Could not persist default overlay selections: $error');
      }
    }
  }
}
