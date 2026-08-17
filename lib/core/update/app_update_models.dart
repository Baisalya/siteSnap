enum AppUpdateRequirement { none, optional, required }

enum AppUpdateResult { success, userDenied, failed }

class StoreUpdateInfo {
  const StoreUpdateInfo({
    required this.updateAvailable,
    required this.immediateUpdateInProgress,
    required this.currentBuildNumber,
    required this.availableBuildNumber,
    required this.immediateUpdateAllowed,
    required this.flexibleUpdateAllowed,
    required this.updatePriority,
    required this.stalenessDays,
  });

  final bool updateAvailable;
  final bool immediateUpdateInProgress;
  final int currentBuildNumber;
  final int availableBuildNumber;
  final bool immediateUpdateAllowed;
  final bool flexibleUpdateAllowed;
  final int updatePriority;
  final int? stalenessDays;

  int get buildGap => availableBuildNumber - currentBuildNumber;
}

class AppUpdatePolicy {
  const AppUpdatePolicy({
    this.requiredBuildGap = 2,
    this.requiredPriority = 4,
    this.requiredStalenessDays = 14,
  });

  final int requiredBuildGap;
  final int requiredPriority;
  final int requiredStalenessDays;

  AppUpdateRequirement evaluate(StoreUpdateInfo info) {
    if (info.immediateUpdateInProgress) return AppUpdateRequirement.required;
    if (!info.updateAvailable || info.buildGap <= 0) {
      return AppUpdateRequirement.none;
    }

    final staleEnough = info.stalenessDays != null &&
        info.stalenessDays! >= requiredStalenessDays;
    if (info.buildGap >= requiredBuildGap ||
        info.updatePriority >= requiredPriority ||
        staleEnough) {
      return AppUpdateRequirement.required;
    }
    return AppUpdateRequirement.optional;
  }
}

class AppUpdateState {
  const AppUpdateState({
    this.isChecking = false,
    this.isUpdating = false,
    this.isSupported = true,
    this.requirement = AppUpdateRequirement.none,
    this.info,
    this.message,
    this.error,
  });

  final bool isChecking;
  final bool isUpdating;
  final bool isSupported;
  final AppUpdateRequirement requirement;
  final StoreUpdateInfo? info;
  final String? message;
  final String? error;

  AppUpdateState copyWith({
    bool? isChecking,
    bool? isUpdating,
    bool? isSupported,
    AppUpdateRequirement? requirement,
    StoreUpdateInfo? info,
    bool clearInfo = false,
    String? message,
    bool clearMessage = false,
    String? error,
    bool clearError = false,
  }) {
    return AppUpdateState(
      isChecking: isChecking ?? this.isChecking,
      isUpdating: isUpdating ?? this.isUpdating,
      isSupported: isSupported ?? this.isSupported,
      requirement: requirement ?? this.requirement,
      info: clearInfo ? null : info ?? this.info,
      message: clearMessage ? null : message ?? this.message,
      error: clearError ? null : error ?? this.error,
    );
  }
}
