import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'overlay_model.dart';
import 'overlay_settings.dart';

/// Immutable visual state consumed by every overlay renderer.
///
/// Keeping data, settings and device orientation together prevents preview,
/// photo and video code paths from reconstructing slightly different overlay
/// states at render time.
class OverlayRenderSnapshot {
  final OverlayData data;
  final OverlaySettings settings;
  final DeviceOrientation orientation;

  const OverlayRenderSnapshot({
    required this.data,
    required this.settings,
    required this.orientation,
  });

  factory OverlayRenderSnapshot.fromJson(Map<String, dynamic> json) {
    return OverlayRenderSnapshot(
      data: OverlayData.fromJson(
        Map<String, dynamic>.from(json['data'] as Map? ?? const {}),
      ),
      settings: OverlaySettings.fromJson(
        Map<String, dynamic>.from(json['settings'] as Map? ?? const {}),
      ),
      orientation: DeviceOrientation.values[
          (json['orientation'] as int? ?? DeviceOrientation.portraitUp.index)
              .clamp(0, DeviceOrientation.values.length - 1)
              .toInt()],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'data': data.toJson(),
      'settings': settings.toJson(),
      'orientation': orientation.index,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is OverlayRenderSnapshot &&
            mapEquals(other.data.toJson(), data.toJson()) &&
            mapEquals(other.settings.toJson(), settings.toJson()) &&
            other.orientation == orientation;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(
            data.toJson().entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAll(
          settings.toJson().entries.map((e) => Object.hash(e.key, e.value)),
        ),
        orientation,
      );
}
