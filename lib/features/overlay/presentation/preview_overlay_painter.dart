import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/overlay_model.dart';
import 'live_overlay_painter.dart';

class PreviewOverlayPainter extends CustomPainter {
  final OverlayData data;
  final bool showOverlay;
  final bool showWatermark;
  final DeviceOrientation orientation;

  PreviewOverlayPainter({
    required this.data,
    required this.showOverlay,
    required this.showWatermark,
    required this.orientation,
  });

  @override
  void paint(Canvas canvas, Size size) {

    /// 📍 MAIN OVERLAY
    if (showOverlay) {
      final painter = LiveOverlayPainter(data, orientation);
      painter.paint(canvas, size);
    }

    /// 🏷 TEXT WATERMARK
    if (showOverlay && showWatermark) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: "SurveyCam",
          style: TextStyle(
            color: Colors.white,
            fontSize: 26, // ✅ FIXED
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                blurRadius: 6,
                color: Colors.black,
                offset: Offset(1, 1),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final padding = size.width * 0.04;

      /// match drawOverlay positioning
      final infoText =
          "${data.dateTime}\n"
          "Lat: ${data.latitude.toStringAsFixed(5)}\n"
          "Lng: ${data.longitude.toStringAsFixed(5)}\n"
          "Alt: ${data.altitude.toStringAsFixed(1)} m\n"
          "${data.direction}";

      final infoPainter = TextPainter(
        text: TextSpan(
          text: infoText,
          style: TextStyle(
            color: Colors.white,
            fontSize: size.width * 0.035,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final infoX = size.width - infoPainter.width - padding;
      final isRightSide = infoX > size.width / 2;

      late Offset offset;

      if (isRightSide) {
        offset = Offset(
          size.width - textPainter.width - padding,
          padding,
        );
      } else {
        offset = Offset(
          padding,
          padding,
        );
      }

      textPainter.paint(canvas, offset);
    }
  }

  @override
  bool shouldRepaint(covariant PreviewOverlayPainter oldDelegate) {
    return oldDelegate.showOverlay != showOverlay ||
        oldDelegate.showWatermark != showWatermark ||
        oldDelegate.data != data;
  }
}
