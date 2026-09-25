import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surveycam/core/monetization/premium_feature.dart';
import 'package:surveycam/core/monetization/premium_policy.dart';
import 'package:surveycam/core/monetization/rewarded_capture_access.dart';
import 'package:surveycam/core/monetization/rewarded_feature_access.dart';
import 'package:surveycam/features/overlay/presentation/overlay_settings_provider.dart';
import 'package:surveycam/features/projects/presentation/project_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer createContainer({bool isPro = false}) {
    return ProviderContainer(overrides: [
      premiumPolicyProvider.overrideWithValue(PremiumPolicy(
        freeLaunchMode: false,
        userHasProPurchase: isPro,
      )),
    ]);
  }

  test('one saved photo spends each rewarded photo feature separately',
      () async {
    final container = createContainer();
    addTearDown(container.dispose);
    final projects = container.read(projectProvider.notifier);
    final overlays = container.read(overlaySettingsProvider.notifier);
    await projects.ready;
    await overlays.ready;

    final project = await projects.createProject('Site A');
    await overlays.setWatermarkTextForSlot(1, 'Company A');
    await overlays.setWatermarkPresetIndex(1);
    await overlays.setBackgroundColor(Colors.blue);
    await overlays.setTextColor(Colors.yellow);
    container.read(rewardedFeatureAccessProvider.notifier).state = {
      PremiumFeature.projectFolders,
      PremiumFeature.customBranding,
      PremiumFeature.overlayColors,
      PremiumFeature.pdfReports,
    };

    await container
        .read(rewardedCaptureAccessProvider)
        .consumeSuccessfulPhoto();

    expect(container.read(rewardedFeatureAccessProvider), {
      PremiumFeature.pdfReports,
    });
    expect(container.read(projectProvider).activeProjectId, isNull);
    expect(container.read(projectProvider).projects.single.id, project.id);
    final settings = container.read(overlaySettingsProvider);
    expect(settings.watermarkPresetIndex, 0);
    expect(settings.watermarkText, 'Company A');
    expect(settings.backgroundColor, Colors.white);
    expect(settings.textColor, Colors.black);
  });

  test('failed background photo restores its one-use reward', () async {
    final container = createContainer();
    addTearDown(container.dispose);
    container.read(rewardedFeatureAccessProvider.notifier).state = {
      PremiumFeature.projectFolders,
    };
    final access = container.read(rewardedCaptureAccessProvider);

    access.reserveBackgroundImage('photo-a.jpg');
    expect(container.read(rewardedFeatureAccessProvider), isEmpty);
    expect(access.isFeaturePending(PremiumFeature.projectFolders), isTrue);
    access.failBackgroundImage('photo-a.jpg');
    expect(access.isFeaturePending(PremiumFeature.projectFolders), isFalse);
    expect(container.read(rewardedFeatureAccessProvider), {
      PremiumFeature.projectFolders,
    });
  });

  test('Pro subscriber keeps settings and is never charged an ad reward',
      () async {
    final container = createContainer(isPro: true);
    addTearDown(container.dispose);
    final overlays = container.read(overlaySettingsProvider.notifier);
    await overlays.ready;
    await overlays.setBackgroundColor(Colors.blue);

    await container
        .read(rewardedCaptureAccessProvider)
        .consumeSuccessfulPhoto();

    expect(
        container.read(overlaySettingsProvider).backgroundColor, Colors.blue);
  });

  test('queued video spends its reward only after a completed save', () async {
    final container = createContainer();
    addTearDown(container.dispose);
    final overlays = container.read(overlaySettingsProvider.notifier);
    await overlays.ready;
    await overlays.setBackgroundColor(Colors.blue);
    container.read(rewardedFeatureAccessProvider.notifier).state = {
      PremiumFeature.overlayColors,
    };
    final access = container.read(rewardedCaptureAccessProvider);

    access.reserveVideo('video-1');
    expect(access.isFeaturePending(PremiumFeature.overlayColors), isTrue);
    expect(container.read(rewardedFeatureAccessProvider), isEmpty);
    await access.completeVideo('video-1');

    expect(access.isFeaturePending(PremiumFeature.overlayColors), isFalse);
    expect(
        container.read(overlaySettingsProvider).backgroundColor, Colors.white);
  });
}
