import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/core/update/app_update_client.dart';
import 'package:surveycam/core/update/app_update_controller.dart';
import 'package:surveycam/core/update/app_update_models.dart';

void main() {
  const policy = AppUpdatePolicy(requiredBuildGap: 2);

  test('cancelling an immediate update cannot bypass mandatory state',
      () async {
    final client = _FakeUpdateClient(
      info: _info(available: 36),
      immediateResult: AppUpdateResult.userDenied,
    );
    final controller = AppUpdateController(client: client, policy: policy);
    addTearDown(controller.dispose);

    await controller.checkForUpdate();
    await controller.startRequiredUpdate();

    expect(controller.state.requirement, AppUpdateRequirement.required);
    expect(controller.state.error, contains('required'));
  });

  test('required update falls back to Play listing when immediate is blocked',
      () async {
    final client = _FakeUpdateClient(
      info: _info(available: 36, immediateAllowed: false),
    );
    final controller = AppUpdateController(client: client, policy: policy);
    addTearDown(controller.dispose);

    await controller.checkForUpdate();
    await controller.startRequiredUpdate();

    expect(client.storeOpenCount, 1);
    expect(controller.state.requirement, AppUpdateRequirement.required);
  });

  test('successful flexible update is completed and dismisses optional banner',
      () async {
    final client = _FakeUpdateClient(info: _info(available: 35));
    final controller = AppUpdateController(client: client, policy: policy);
    addTearDown(controller.dispose);

    await controller.checkForUpdate();
    expect(controller.state.requirement, AppUpdateRequirement.optional);

    await controller.startOptionalUpdate();

    expect(client.flexibleCount, 1);
    expect(controller.state.requirement, AppUpdateRequirement.none);
  });

  test('failed flexible update stays optional so the user can retry', () async {
    final client = _FakeUpdateClient(
      info: _info(available: 35),
      flexibleResult: AppUpdateResult.failed,
    );
    final controller = AppUpdateController(client: client, policy: policy);
    addTearDown(controller.dispose);

    await controller.checkForUpdate();
    await controller.startOptionalUpdate();

    expect(controller.state.requirement, AppUpdateRequirement.optional);
    expect(controller.state.error, isNotNull);
  });

  test('a failed first update check never locks an offline user', () async {
    final client = _FakeUpdateClient(checkError: StateError('offline'));
    final controller = AppUpdateController(client: client, policy: policy);
    addTearDown(controller.dispose);

    await controller.checkForUpdate();

    expect(controller.state.requirement, AppUpdateRequirement.none);
    expect(controller.state.error, isNotNull);
  });

  test('a retry failure cannot clear established mandatory state', () async {
    final client = _FakeUpdateClient(info: _info(available: 36));
    final controller = AppUpdateController(client: client, policy: policy);
    addTearDown(controller.dispose);
    await controller.checkForUpdate();
    client.checkError = StateError('offline');

    await controller.checkForUpdate();

    expect(controller.state.requirement, AppUpdateRequirement.required);
  });

  test('an unsupported retry cannot clear established mandatory state',
      () async {
    final client = _FakeUpdateClient(info: _info(available: 36));
    final controller = AppUpdateController(client: client, policy: policy);
    addTearDown(controller.dispose);
    await controller.checkForUpdate();
    client.info = null;

    await controller.checkForUpdate();

    expect(controller.state.requirement, AppUpdateRequirement.required);
    expect(controller.state.info, isNotNull);
  });
}

StoreUpdateInfo _info({
  required int available,
  bool immediateAllowed = true,
}) {
  return StoreUpdateInfo(
    updateAvailable: available > 34,
    immediateUpdateInProgress: false,
    currentBuildNumber: 34,
    availableBuildNumber: available,
    immediateUpdateAllowed: immediateAllowed,
    flexibleUpdateAllowed: true,
    updatePriority: 0,
    stalenessDays: 0,
  );
}

class _FakeUpdateClient implements AppUpdateClient {
  _FakeUpdateClient({
    this.info,
    this.immediateResult = AppUpdateResult.success,
    this.flexibleResult = AppUpdateResult.success,
    this.checkError,
  });

  StoreUpdateInfo? info;
  AppUpdateResult immediateResult;
  AppUpdateResult flexibleResult;
  Object? checkError;
  int storeOpenCount = 0;
  int flexibleCount = 0;

  @override
  bool get isSupported => true;

  @override
  Future<StoreUpdateInfo?> checkForUpdate() async {
    if (checkError case final error?) throw error;
    return info;
  }

  @override
  Future<void> openStoreListing() async => storeOpenCount++;

  @override
  Future<AppUpdateResult> performFlexibleUpdate() async {
    flexibleCount++;
    return flexibleResult;
  }

  @override
  Future<AppUpdateResult> performImmediateUpdate() async => immediateResult;
}
