import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/WatermarkPosition.dart';
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
    if (size.width == 0 || size.height == 0) return;

    /// 📍 MAIN OVERLAY
    if (showOverlay) {
      final painter = LiveOverlayPainter(data, orientation);
      painter.paint(canvas, size);
    }

    /// 📍 WATERMARK (SurveyCam)
    if (showWatermark) {
      _drawWatermark(canvas, size);
    }
  }

  void _drawWatermark(Canvas canvas, Size size) {
    canvas.save();

    // ===============================
    // ROTATE CANVAS (Consistent with LiveOverlayPainter)
    // ===============================
    switch (orientation) {
      case DeviceOrientation.portraitUp:
        break;
      case DeviceOrientation.portraitDown:
        canvas.translate(size.width, size.height);
        canvas.rotate(pi);
        break;
      case DeviceOrientation.landscapeLeft:
        canvas.translate(0, size.height);
        canvas.rotate(-pi / 2);
        break;
      case DeviceOrientation.landscapeRight:
        canvas.translate(size.width, 0);
        canvas.rotate(pi / 2);
        break;
    }

    double drawWidth = size.width;
    double drawHeight = size.height;

    if (orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight) {
      drawWidth = size.height;
      drawHeight = size.width;
    }

    final baseSize = min(drawWidth, drawHeight);

    // ===============================
    // TEXT STYLE
    // ===============================
    final textPainter = TextPainter(
      text: TextSpan(
        text: "SurveyCam",
        style: TextStyle(
          color: Colors.white,
          fontSize: baseSize * 0.045, // Proportional size
          fontWeight: FontWeight.bold,
          shadows: const [
            Shadow(
              blurRadius: 4,
              color: Colors.black54,
              offset: Offset(1, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // ===============================
    // POSITIONING
    // ===============================
    final padding = drawWidth * 0.04;

    // Place it at the TOP (opposite of info box which is at bottom)
    // Horizontal side matches the info box side
    final isRightSide = data.position != WatermarkPosition.bottomLeft;

    final dx = isRightSide
        ? drawWidth - textPainter.width - padding
        : padding;
    
    final dy = padding; // Always at the top for the watermark

    textPainter.paint(canvas, Offset(dx, dy));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PreviewOverlayPainter oldDelegate) {
    return oldDelegate.showOverlay != showOverlay ||
        oldDelegate.showWatermark != showWatermark ||
        oldDelegate.data != data ||
        oldDelegate.orientation != orientation;
  }
}
