import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/core/utils/device_orientation_provider.dart';

void main() {
  group('photo/preview legacy orientation contract', () {
    test('keeps portrait gravity directions unchanged', () {
      expect(
        uiPhotoOrientationFromAccelerometer(x: 0, y: 9.8),
        DeviceOrientation.portraitUp,
      );
      expect(
        uiPhotoOrientationFromAccelerometer(x: 0, y: -9.8),
        DeviceOrientation.portraitDown,
      );
    });

    test('keeps established landscape labels used by PHOTO', () {
      expect(
        uiPhotoOrientationFromAccelerometer(x: 9.8, y: 0),
        DeviceOrientation.landscapeRight,
      );
      expect(
        uiPhotoOrientationFromAccelerometer(x: -9.8, y: 0),
        DeviceOrientation.landscapeLeft,
      );
    });

    test('ignores ambiguous near-flat readings', () {
      expect(
        uiPhotoOrientationFromAccelerometer(x: 3.0, y: 4.0),
        isNull,
      );
    });
  });
}
