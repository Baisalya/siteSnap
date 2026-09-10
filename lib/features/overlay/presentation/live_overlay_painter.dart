import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:surveycam/features/overlay/domain/overlay_model.dart';
import 'package:surveycam/features/overlay/domain/overlay_render_snapshot.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';
import 'package:surveycam/features/overlay/presentation/overlay_layout_engine.dart';

class LiveOverlayPainter extends CustomPainter {
  final OverlayRenderSnapshot snapshot;

  LiveOverlayPainter(
    OverlayData data,
    DeviceOrientation orientation, {
    OverlaySettings settings = const OverlaySettings(),
  }) : snapshot = OverlayRenderSnapshot(
          data: data,
          settings: settings,
          orientation: orientation,
        );

  LiveOverlayPainter.snapshot(this.snapshot);

  OverlayData get data => snapshot.data;
  DeviceOrientation get orientation => snapshot.orientation;
  OverlaySettings get settings => snapshot.settings;

  @override
  void paint(Canvas canvas, Size size) {
    OverlayCardRenderer.paint(
      canvas: canvas,
      size: size,
      snapshot: snapshot,
    );
  }

  @override
  bool shouldRepaint(covariant LiveOverlayPainter oldDelegate) {
    return oldDelegate.snapshot != snapshot;
  }
}
