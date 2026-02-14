import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

final deviceOrientationProvider =
StateNotifierProvider<DeviceOrientationNotifier,
    DeviceOrientation>((ref) {
  return DeviceOrientationNotifier();
});

class DeviceOrientationNotifier
    extends StateNotifier<DeviceOrientation> {

  DeviceOrientationNotifier()
      : super(DeviceOrientation.portraitUp) {
    _startListening();
  }

  StreamSubscription? _subscription;

  static const double _threshold = 6.0;

  void _startListening() {
    _subscription =
        accelerometerEvents.listen((event) {

          final x = event.x;
          final y = event.y;

          DeviceOrientation? newOrientation;

          if (x.abs() > y.abs()) {
            // LANDSCAPE
            if (x > _threshold) {
              newOrientation =
                  DeviceOrientation.landscapeRight;
            } else if (x < -_threshold) {
              newOrientation =
                  DeviceOrientation.landscapeLeft;
            }
          } else {
            // PORTRAIT (fixed direction)
            if (y > _threshold) {
              newOrientation =
                  DeviceOrientation.portraitUp;
            } else if (y < -_threshold) {
              newOrientation =
                  DeviceOrientation.portraitDown;
            }
          }

          if (newOrientation != null &&
              newOrientation != state) {
            state = newOrientation;
          }
        });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
