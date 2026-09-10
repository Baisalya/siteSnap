import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:sensors_plus/sensors_plus.dart';

final deviceOrientationProvider =
    StateNotifierProvider<DeviceOrientationNotifier, DeviceOrientation>((ref) {
  return DeviceOrientationNotifier();
});

/// Legacy UI/photo orientation contract.
///
/// Do not reuse this mapping as CameraX VideoCapture target rotation. The photo
/// and preview pipeline relied on these labels before realtime-video work and
/// must remain stable. Video uses `toVideoCaptureOrientation` instead.
DeviceOrientation? uiPhotoOrientationFromAccelerometer({
  required double x,
  required double y,
  double threshold = 6.0,
}) {
  if (x.abs() > y.abs()) {
    if (x > threshold) return DeviceOrientation.landscapeRight;
    if (x < -threshold) return DeviceOrientation.landscapeLeft;
    return null;
  }
  if (y > threshold) return DeviceOrientation.portraitUp;
  if (y < -threshold) return DeviceOrientation.portraitDown;
  return null;
}

class DeviceOrientationNotifier extends StateNotifier<DeviceOrientation> {
  DeviceOrientationNotifier() : super(DeviceOrientation.portraitUp) {
    _startListening();
  }

  StreamSubscription? _subscription;

  static const double _threshold = 6.0;

  void _startListening() {
    _subscription = accelerometerEvents.listen((event) {
      final x = event.x;
      final y = event.y;

      DeviceOrientation? newOrientation;

      if (x.abs() > y.abs()) {
        // LANDSCAPE
        if (x > _threshold) {
          newOrientation = DeviceOrientation.landscapeRight;
        } else if (x < -_threshold) {
          newOrientation = DeviceOrientation.landscapeLeft;
        }
      } else {
        // PORTRAIT (fixed direction)
        if (y > _threshold) {
          newOrientation = DeviceOrientation.portraitUp;
        } else if (y < -_threshold) {
          newOrientation = DeviceOrientation.portraitDown;
        }
      }

      if (newOrientation != null && newOrientation != state) {
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
