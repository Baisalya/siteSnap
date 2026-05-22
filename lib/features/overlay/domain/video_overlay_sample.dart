import 'package:flutter/services.dart';
import 'overlay_model.dart';
import 'overlay_settings.dart';

class VideoOverlaySample {
  final OverlayData data;
  final DeviceOrientation orientation;
  final OverlaySettings settings;
  final int timestampMs;

  const VideoOverlaySample({
    required this.data,
    required this.orientation,
    required this.settings,
    required this.timestampMs,
  });
}
