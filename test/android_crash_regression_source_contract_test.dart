import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native callback and worker patches are included in the Android build',
      () {
    final gradle = File('android/build.gradle').readAsStringSync();
    expect(
        gradle,
        contains(
            "exclude 'io/flutter/plugins/camerax/CameraControlProxyApi.java'"));
    final activity = File(
      'android/app/src/main/kotlin/com/baishalya/sitesnap/MainActivity.kt',
    ).readAsStringSync();
    for (final method in [
      'listSurveyCamMedia',
      'getLastAppExitInfo',
      'getUsableStorageBytes',
    ]) {
      expect(activity, contains('"$method" -> ioCalls.submit(result)'));
    }
    expect(activity, contains('backgroundCalls?.close()'));
    final photo = File('android/camerax_patch/ImageCaptureProxyApi.java')
        .readAsStringSync();
    expect(photo, contains('ContextCompat.getMainExecutor('));
    expect(photo, contains('.setIoExecutor(PHOTO_EXECUTOR)'));
  });

  test('all video transitions share one queue without recursive queue waits',
      () {
    final source = File(
      'lib/features/camera/presentation/camera_viewmodel.dart',
    ).readAsStringSync();
    expect(source, contains('_sessionQueue.run(_switchCameraInternal)'));
    expect(source, contains('_sessionQueue.run(_refreshCameraInternal)'));
    expect(source, contains('() => _startVideoRecordingInternal('));
    expect(source, contains('() => _stopVideoRecordingInternal('));
    expect(source, contains('.run(() => _handleLifecycleState('));
    expect(source, contains('_sessionQueue.run(repository.dispose)'));
    final lifecycle = source.substring(
      source.indexOf('Future<void> _handleLifecycleState('),
      source.indexOf('// ================= REFRESH ================='),
    );
    expect(lifecycle, contains('await _stopVideoRecordingInternal()'));
    expect(
        lifecycle, isNot(contains('await stopVideoRecordingInBackground()')));
    expect(
        source, contains('if (!await _canContinueRecordingSwitch()) return;'));
  });
}
