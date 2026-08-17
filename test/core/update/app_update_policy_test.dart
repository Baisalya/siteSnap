import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/core/update/app_update_models.dart';

void main() {
  const policy = AppUpdatePolicy(
    requiredBuildGap: 2,
    requiredPriority: 4,
    requiredStalenessDays: 14,
  );

  test('no newer build requires no update', () {
    expect(policy.evaluate(_info(available: 34)), AppUpdateRequirement.none);
  });

  test('one-build gap is optional while fresh and low priority', () {
    expect(
        policy.evaluate(_info(available: 35)), AppUpdateRequirement.optional);
  });

  test('two-build gap is mandatory', () {
    expect(
        policy.evaluate(_info(available: 36)), AppUpdateRequirement.required);
  });

  test('Play priority can make the next build mandatory', () {
    expect(
      policy.evaluate(_info(available: 35, priority: 4)),
      AppUpdateRequirement.required,
    );
  });

  test('stale update becomes mandatory', () {
    expect(
      policy.evaluate(_info(available: 35, staleDays: 14)),
      AppUpdateRequirement.required,
    );
  });

  test('developer-triggered immediate update stays mandatory', () {
    expect(
      policy.evaluate(_info(available: 35, inProgress: true)),
      AppUpdateRequirement.required,
    );
  });
}

StoreUpdateInfo _info({
  required int available,
  int priority = 0,
  int? staleDays,
  bool inProgress = false,
}) {
  return StoreUpdateInfo(
    updateAvailable: available > 34,
    immediateUpdateInProgress: inProgress,
    currentBuildNumber: 34,
    availableBuildNumber: available,
    immediateUpdateAllowed: true,
    flexibleUpdateAllowed: true,
    updatePriority: priority,
    stalenessDays: staleDays,
  );
}
