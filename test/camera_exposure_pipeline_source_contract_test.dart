import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exposure gesture coalesces native work before capture', () {
    final source = File(
      'lib/features/camera/presentation/camera_viewmodel.dart',
    ).readAsStringSync();

    final exposureStart =
        source.indexOf('// ================= EXPOSURE =================');
    final exposureEnd =
        source.indexOf('// ================= ZOOM =================');
    expect(exposureStart, greaterThanOrEqualTo(0));
    expect(exposureEnd, greaterThan(exposureStart));

    final exposureSection = source.substring(exposureStart, exposureEnd);
    expect(exposureSection, contains('void changeExposure(double delta)'));
    expect(
        exposureSection, contains('state = state.copyWith(exposure: target)'));
    expect(exposureSection, contains('_exposureUpdates.submit('));
    expect(exposureSection, contains('_exposureUpdates.flush('));
    expect(exposureSection, isNot(contains("'exposure offset'")));

    final captureStart = source.indexOf('Future<String?> capture()');
    final recordingCaptureStart =
        source.indexOf('Future<bool> capturePhotoDuringRecording()');
    expect(captureStart, greaterThanOrEqualTo(0));
    expect(recordingCaptureStart, greaterThan(captureStart));

    final normalCapture = source.substring(captureStart, recordingCaptureStart);
    expect(normalCapture, contains('_settleExposureForCapture(controller)'));
    expect(normalCapture, contains('.timeout(_photoCaptureTimeout)'));
  });
}
