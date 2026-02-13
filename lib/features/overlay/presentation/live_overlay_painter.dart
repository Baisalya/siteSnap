import 'dart:math';
import 'package:flutter/material.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

import '../domain/overlay_model.dart';
import '../domain/WatermarkPosition.dart';

class LiveOverlayPainter extends CustomPainter {
  final OverlayData data;
  final NativeDeviceOrientation orientation;

  LiveOverlayPainter(this.data, this.orientation);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width == 0 || size.height == 0) return;

    canvas.save();

    // ===============================
    // ROTATE CANVAS (CORRECT TYPE)
    // ===============================
    if (orientation ==
        NativeDeviceOrientation.landscapeLeft) {
      canvas.translate(size.width, 0);
      canvas.rotate(pi / 2);
    } else if (orientation ==
        NativeDeviceOrientation.landscapeRight) {
      canvas.translate(0, size.height);
      canvas.rotate(-pi / 2);
    } else if (orientation ==
        NativeDeviceOrientation.portraitDown) {
      canvas.translate(size.width, size.height);
      canvas.rotate(pi);
    }

    // ===============================
    // DRAW SIZE FIX
    // ===============================
    double drawWidth = size.width;
    double drawHeight = size.height;

    if (orientation ==
        NativeDeviceOrientation.landscapeLeft ||
        orientation ==
            NativeDeviceOrientation.landscapeRight) {
      drawWidth = size.height;
      drawHeight = size.width;
    }

    // ===============================
    // TEXT STYLE
    // ===============================
    final baseSize = min(drawWidth, drawHeight);

    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: baseSize * 0.035,
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
    // POSITIONING
    // ===============================
    final marginX = drawWidth * 0.03;
    final marginY = drawHeight * 0.03;

    final dx = data.position ==
        WatermarkPosition.bottomLeft
        ? marginX
        : drawWidth - textPainter.width - marginX;

    final dy =
        drawHeight - textPainter.height - marginY;

    final offset = Offset(dx, dy);

    // ===============================
    // BACKGROUND
    // ===============================
    final bgRect = Rect.fromLTWH(
      offset.dx - drawWidth * 0.01,
      offset.dy - drawHeight * 0.01,
      textPainter.width + drawWidth * 0.02,
      textPainter.height + drawHeight * 0.02,
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
