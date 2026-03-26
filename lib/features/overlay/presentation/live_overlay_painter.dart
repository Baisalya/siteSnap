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
    // ROTATE CANVAS
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

    final baseSize = min(drawWidth, drawHeight);

    // ===============================
    // PROFESSIONAL TEXT STYLE
    // ===============================
    final textStyle = TextStyle(
      color: data.locationWarning != null
          ? Colors.redAccent
          : Colors.black87,
      fontSize: baseSize * 0.038, // slightly larger
      fontWeight: FontWeight.w500,
      height: 1.25,
      letterSpacing: 0.3,
      shadows: const [
        Shadow(
          offset: Offset(0.5, 0.5),
          blurRadius: 2,
          color: Colors.white60,
        ),
      ],
    );

    // ===============================
    // BUILD TEXT
    // ===============================
    final buffer = StringBuffer();

    if (data.dateTime.isNotEmpty) {
      buffer.writeln(data.dateTime);
    }

    if (data.locationWarning != null) {
      buffer.writeln(data.locationWarning);
    } else {
      buffer.writeln(
          "Lat ${data.latitude.toStringAsFixed(5)}  |  Lon ${data.longitude.toStringAsFixed(5)}");
    }

    buffer.writeln(
        "Alt ${data.altitude.toStringAsFixed(1)} m  |  ${data.direction} ${data.heading.toStringAsFixed(0)}°");

    if (data.note.isNotEmpty) {
      buffer.writeln(data.note);
    }

    final text = buffer.toString();

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 6,
      ellipsis: '…',
    );

    textPainter.layout(maxWidth: drawWidth * 0.82);

    // ===============================
    // POSITION
    // ===============================
    final marginX = drawWidth * 0.03;
    final marginY = drawHeight * 0.03;

    final dx = data.position == WatermarkPosition.bottomLeft
        ? marginX
        : drawWidth - textPainter.width - marginX;

    final dy = drawHeight - textPainter.height - marginY;

    final offset = Offset(dx, dy);

    // ===============================
    // PROFESSIONAL BACKGROUND CARD
    // ===============================
    final bgRect = Rect.fromLTWH(
      offset.dx - drawWidth * 0.018,
      offset.dy - drawHeight * 0.018,
      textPainter.width + drawWidth * 0.036,
      textPainter.height + drawHeight * 0.036,
    );

    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.40);

    // soft shadow
    canvas.drawShadow(
      Path()..addRRect(RRect.fromRectAndRadius(bgRect, const Radius.circular(10))),
      Colors.black.withOpacity(0.35),
      6,
      false,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bgRect,
        const Radius.circular(10),
      ),
      bgPaint,
    );

    // ===============================
    // DRAW TEXT
    // ===============================
    textPainter.paint(canvas, offset);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LiveOverlayPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.orientation != orientation;
  }
}