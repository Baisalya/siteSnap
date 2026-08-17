import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart' as play;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update_client.dart';
import 'app_update_config.dart';
import 'app_update_models.dart';

class PlayAppUpdateClient implements AppUpdateClient {
  @override
  bool get isSupported => Platform.isAndroid && kReleaseMode;

  @override
  Future<StoreUpdateInfo?> checkForUpdate() async {
    if (!isSupported) return null;

    final packageInfo = await PackageInfo.fromPlatform();
    final installer = packageInfo.installerStore;
    if (installer == null || !installer.contains('vending')) return null;

    final info = await play.InAppUpdate.checkForUpdate();
    final availability = info.updateAvailability;
    return StoreUpdateInfo(
      updateAvailable:
          availability == play.UpdateAvailability.updateAvailable ||
              availability ==
                  play.UpdateAvailability.developerTriggeredUpdateInProgress,
      immediateUpdateInProgress: availability ==
          play.UpdateAvailability.developerTriggeredUpdateInProgress,
      currentBuildNumber: int.tryParse(packageInfo.buildNumber) ?? 0,
      availableBuildNumber: info.availableVersionCode ?? 0,
      immediateUpdateAllowed: info.immediateUpdateAllowed,
      flexibleUpdateAllowed: info.flexibleUpdateAllowed,
      updatePriority: info.updatePriority,
      stalenessDays: info.clientVersionStalenessDays,
    );
  }

  @override
  Future<AppUpdateResult> performImmediateUpdate() async {
    final result = await play.InAppUpdate.performImmediateUpdate();
    return _mapResult(result);
  }

  @override
  Future<AppUpdateResult> performFlexibleUpdate() async {
    final result = await play.InAppUpdate.startFlexibleUpdate();
    if (result == play.AppUpdateResult.success) {
      await play.InAppUpdate.completeFlexibleUpdate();
    }
    return _mapResult(result);
  }

  @override
  Future<void> openStoreListing() async {
    final marketUri = Uri.parse(
      'market://details?id=${AppUpdateConfig.androidPackageName}',
    );
    if (await canLaunchUrl(marketUri)) {
      await launchUrl(marketUri, mode: LaunchMode.externalApplication);
      return;
    }
    await launchUrl(
      Uri.parse(
        'https://play.google.com/store/apps/details'
        '?id=${AppUpdateConfig.androidPackageName}',
      ),
      mode: LaunchMode.externalApplication,
    );
  }

  AppUpdateResult _mapResult(play.AppUpdateResult result) {
    return switch (result) {
      play.AppUpdateResult.success => AppUpdateResult.success,
      play.AppUpdateResult.userDeniedUpdate => AppUpdateResult.userDenied,
      play.AppUpdateResult.inAppUpdateFailed => AppUpdateResult.failed,
    };
  }
}
