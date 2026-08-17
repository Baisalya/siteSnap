import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'app_update_client.dart';
import 'app_update_config.dart';
import 'app_update_models.dart';
import 'play_app_update_client.dart';

final appUpdateClientProvider = Provider<AppUpdateClient>((ref) {
  return PlayAppUpdateClient();
});

final appUpdatePolicyProvider = Provider<AppUpdatePolicy>((ref) {
  return const AppUpdatePolicy(
    requiredBuildGap: AppUpdateConfig.requiredBuildGap,
    requiredPriority: AppUpdateConfig.requiredPriority,
    requiredStalenessDays: AppUpdateConfig.requiredStalenessDays,
  );
});

final appUpdateControllerProvider =
    StateNotifierProvider<AppUpdateController, AppUpdateState>((ref) {
  return AppUpdateController(
    client: ref.watch(appUpdateClientProvider),
    policy: ref.watch(appUpdatePolicyProvider),
  );
});

class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController({
    required AppUpdateClient client,
    required AppUpdatePolicy policy,
  })  : _client = client,
        _policy = policy,
        super(AppUpdateState(isSupported: client.isSupported));

  final AppUpdateClient _client;
  final AppUpdatePolicy _policy;
  Future<void>? _activeCheck;

  Future<void> checkForUpdate() {
    return _activeCheck ??= _checkForUpdate().whenComplete(() {
      _activeCheck = null;
    });
  }

  Future<void> _checkForUpdate() async {
    if (!_client.isSupported) {
      state = state.copyWith(
        isChecking: false,
        isSupported: false,
        requirement: AppUpdateRequirement.none,
        clearInfo: true,
      );
      return;
    }

    state = state.copyWith(
      isChecking: true,
      isSupported: true,
      clearError: true,
    );
    try {
      final info = await _client.checkForUpdate();
      if (!mounted) return;
      if (info == null) {
        final keepRequired = state.requirement == AppUpdateRequirement.required;
        state = state.copyWith(
          isChecking: false,
          isSupported: false,
          requirement: keepRequired
              ? AppUpdateRequirement.required
              : AppUpdateRequirement.none,
          clearInfo: !keepRequired,
          error: keepRequired
              ? 'Google Play could not verify the installed version. Retry the check.'
              : null,
          clearError: !keepRequired,
        );
        return;
      }
      state = state.copyWith(
        isChecking: false,
        requirement: _policy.evaluate(info),
        info: info,
        clearMessage: true,
        clearError: true,
      );
    } catch (error, stackTrace) {
      debugPrint('Play update check failed: $error\n$stackTrace');
      if (!mounted) return;

      // A temporary network/Play failure must not lock a previously usable
      // app. If this session already established a mandatory requirement,
      // however, do not allow a retry failure to bypass it.
      state = state.copyWith(
        isChecking: false,
        error: state.requirement == AppUpdateRequirement.required
            ? 'Could not contact Google Play. Check your connection and retry.'
            : 'Could not check for updates right now.',
      );
    }
  }

  Future<void> startRequiredUpdate() async {
    final info = state.info;
    if (state.isUpdating || info == null) return;

    state = state.copyWith(
      isUpdating: true,
      clearError: true,
      message: 'Opening the secure Google Play update…',
    );
    try {
      if (!info.immediateUpdateAllowed) {
        await _client.openStoreListing();
        if (mounted) {
          state = state.copyWith(
            isUpdating: false,
            message:
                'Install the latest version from Google Play, then return.',
          );
        }
        return;
      }

      final result = await _client.performImmediateUpdate();
      if (!mounted) return;
      switch (result) {
        case AppUpdateResult.success:
          state = state.copyWith(
            isUpdating: false,
            message: 'Update installed. Restart SurveyCam if needed.',
            clearError: true,
          );
        case AppUpdateResult.userDenied:
          state = state.copyWith(
            isUpdating: false,
            error: 'This update is required to continue using SurveyCam.',
            clearMessage: true,
          );
        case AppUpdateResult.failed:
          state = state.copyWith(
            isUpdating: false,
            error: 'Google Play could not install the update. Please retry.',
            clearMessage: true,
          );
      }
    } catch (error, stackTrace) {
      debugPrint('Required update failed: $error\n$stackTrace');
      if (mounted) {
        state = state.copyWith(
          isUpdating: false,
          error: 'Update failed. Check storage and internet, then retry.',
          clearMessage: true,
        );
      }
    }
  }

  Future<void> startOptionalUpdate() async {
    final info = state.info;
    if (state.isUpdating || info == null) return;
    if (!info.flexibleUpdateAllowed) {
      await openStoreListing();
      return;
    }

    state = state.copyWith(
      isUpdating: true,
      clearError: true,
      message: 'Downloading the update from Google Play…',
    );
    try {
      final result = await _client.performFlexibleUpdate();
      if (!mounted) return;
      switch (result) {
        case AppUpdateResult.success:
          state = state.copyWith(
            isUpdating: false,
            requirement: AppUpdateRequirement.none,
            message: 'Update ready. SurveyCam will restart to install it.',
            clearError: true,
          );
        case AppUpdateResult.userDenied:
          dismissOptionalUpdate();
        case AppUpdateResult.failed:
          state = state.copyWith(
            isUpdating: false,
            error: 'The update could not be installed. You can retry later.',
            clearMessage: true,
          );
      }
    } catch (error, stackTrace) {
      debugPrint('Optional update failed: $error\n$stackTrace');
      if (mounted) {
        state = state.copyWith(
          isUpdating: false,
          error: 'The update could not be installed. You can retry later.',
          clearMessage: true,
        );
      }
    }
  }

  void dismissOptionalUpdate() {
    if (state.requirement != AppUpdateRequirement.optional) return;
    state = state.copyWith(
      isUpdating: false,
      requirement: AppUpdateRequirement.none,
      clearMessage: true,
      clearError: true,
    );
  }

  Future<void> openStoreListing() async {
    try {
      await _client.openStoreListing();
    } catch (error, stackTrace) {
      debugPrint('Could not open Google Play listing: $error\n$stackTrace');
      if (mounted) {
        state = state.copyWith(
          isUpdating: false,
          error:
              'Could not open Google Play. Open Play Store and search for SurveyCam.',
        );
      }
    }
  }
}
