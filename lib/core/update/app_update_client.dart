import 'app_update_models.dart';

abstract interface class AppUpdateClient {
  bool get isSupported;

  Future<StoreUpdateInfo?> checkForUpdate();

  Future<AppUpdateResult> performImmediateUpdate();

  Future<AppUpdateResult> performFlexibleUpdate();

  Future<void> openStoreListing();
}
