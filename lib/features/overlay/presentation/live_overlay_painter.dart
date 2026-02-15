import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/overlay_model.dart';
import '../domain/WatermarkPosition.dart';

class LiveOverlayPainter extends CustomPainter {
  final OverlayData data;
  final DeviceOrientation orientation;

  LiveOverlayPainter(this.data, this.orientation);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width == 0 || size.height == 0) return;

    canvas.save();

    // ===============================
// ROTATE CANVAS (FIXED)
// ===============================
    // ===============================
// ROTATE CANVAS (LANDSCAPE FIX)
// ===============================
    switch (orientation) {

      case DeviceOrientation.portraitUp:
      // no rotation
        break;

      case DeviceOrientation.portraitDown:
        canvas.translate(size.width, size.height);
        canvas.rotate(pi);
        break;

    // FIXED (swapped rotations)
      case DeviceOrientation.landscapeLeft:
        canvas.translate(0, size.height);
        canvas.rotate(-pi / 2);
        break;

      case DeviceOrientation.landscapeRight:
        canvas.translate(size.width, 0);
        canvas.rotate(pi / 2);
        break;
    }


    // portraitUp → no rotation

    // ===============================
    // DRAW SIZE FIX
    // ===============================
    double drawWidth = size.width;
    double drawHeight = size.height;

    if (orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight) {
      drawWidth = size.height;
      drawHeight = size.width;
    }

    // ===============================
    // TEXT STYLE
    // ===============================
    final baseSize = min(drawWidth, drawHeight);

    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: baseSize * 0.045,
      height: 1.25,
      shadows: const [
        Shadow(
          offset: Offset(1.5, 1.5),
          blurRadius: 4,
          color: Colors.black,
        ),
      ],
    );

    final text = '''
${data.dateTime}
Latitude: ${data.latitude.toStringAsFixed(5)}, Longitude: ${data.longitude.toStringAsFixed(5)}
Altitude: ${data.altitude.toStringAsFixed(1)} m
Dir: ${data.direction} (${data.heading.toStringAsFixed(0)}°)
${data.note}
''';

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 6,
      ellipsis: '…',
    );

    textPainter.layout(maxWidth: drawWidth * 0.9);

    // ===============================
    // POSITIONING (NO ORIENTATION CHECK)
    // ===============================
    final marginX = drawWidth * 0.03;
    final marginY = drawHeight * 0.03;

    final dx = data.position == WatermarkPosition.bottomLeft
        ? marginX
        : drawWidth - textPainter.width - marginX;

    // ALWAYS draw at bottom
    final dy =
        drawHeight - textPainter.height - marginY;

    final offset = Offset(dx, dy);

    // ===============================
    // BACKGROUND
    // ===============================
    final bgRect = Rect.fromLTWH(
      offset.dx - drawWidth * 0.015,
      offset.dy - drawHeight * 0.015,
      textPainter.width + drawWidth * 0.03,
      textPainter.height + drawHeight * 0.03,

    );

    final bgPaint = Paint()
      ..color = Colors.black.withOpacity(0.45);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bgRect,
        const Radius.circular(8),
      ),
      bgPaint,
    );

    textPainter.paint(canvas, offset);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LiveOverlayPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.orientation != orientation;
  }
}
