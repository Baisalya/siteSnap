import 'package:flutter/services.dart';

import 'overlay_model.dart';
import 'overlay_render_snapshot.dart';
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

  factory VideoOverlaySample.fromSnapshot(
    OverlayRenderSnapshot snapshot, {
    required int timestampMs,
  }) {
    return VideoOverlaySample(
      data: snapshot.data,
      orientation: snapshot.orientation,
      settings: snapshot.settings,
      timestampMs: timestampMs,
    );
  }

  OverlayRenderSnapshot get snapshot => OverlayRenderSnapshot(
        data: data,
        settings: settings,
        orientation: orientation,
      );

  factory VideoOverlaySample.fromJson(Map<String, dynamic> json) {
    return VideoOverlaySample(
      data: OverlayData.fromJson(
          Map<String, dynamic>.from(json['data'] as Map? ?? const {})),
      orientation: DeviceOrientation.values[
          (json['orientation'] as int? ?? DeviceOrientation.portraitUp.index)
              .clamp(0, DeviceOrientation.values.length - 1)
              .toInt()],
      settings: OverlaySettings.fromJson(
          Map<String, dynamic>.from(json['settings'] as Map? ?? const {})),
      timestampMs: json['timestampMs'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'data': data.toJson(),
      'orientation': orientation.index,
      'settings': settings.toJson(),
      'timestampMs': timestampMs,
    };
  }
}
