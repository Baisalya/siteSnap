class AppUpdateConfig {
  const AppUpdateConfig._();

  /// A one-build gap is offered as an optional update. Users two or more
  /// builds behind are blocked until they update.
  static const int requiredBuildGap = int.fromEnvironment(
    'SURVEYCAM_REQUIRED_UPDATE_GAP',
    defaultValue: 2,
  );

  /// Google Play update priorities range from 0 to 5.
  static const int requiredPriority = int.fromEnvironment(
    'SURVEYCAM_REQUIRED_UPDATE_PRIORITY',
    defaultValue: 4,
  );

  static const int requiredStalenessDays = int.fromEnvironment(
    'SURVEYCAM_REQUIRED_UPDATE_STALENESS_DAYS',
    defaultValue: 14,
  );

  static const String androidPackageName = 'com.baishalya.surveycam';
}
