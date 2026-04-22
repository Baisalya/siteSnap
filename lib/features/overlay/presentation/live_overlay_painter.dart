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
      color: Colors.black,
      fontSize: baseSize * 0.032, // More refined size
      fontWeight: FontWeight.w600,
      height: 1.2,
      letterSpacing: 0.2,
    );

    final warningStyle = textStyle.copyWith(color: Colors.redAccent);
    final noteStyle = textStyle.copyWith(
      fontSize: baseSize * 0.035, 
      color: Colors.blueGrey[900],
      fontStyle: FontStyle.italic,
    );

    // ===============================
    // BUILD TEXT SPANS
    // ===============================
    final List<TextSpan> spans = [];

    if (data.dateTime.isNotEmpty) {
      spans.add(TextSpan(text: "${data.dateTime}\n", style: textStyle));
    }

    if (data.locationWarning != null) {
      spans.add(TextSpan(text: "${data.locationWarning}\n", style: warningStyle));
    } else {
      spans.add(TextSpan(
        text: "LAT: ${data.latitude.toStringAsFixed(6)}  LON: ${data.longitude.toStringAsFixed(6)}\n",
        style: textStyle,
      ));
    }

    spans.add(TextSpan(
      text: "ALT: ${data.altitude.toStringAsFixed(1)}m  DIR: ${data.direction} ${data.heading.toStringAsFixed(0)}°\n",
      style: textStyle,
    ));

    if (data.note.isNotEmpty) {
      spans.add(TextSpan(text: data.note, style: noteStyle));
    }

    final textPainter = TextPainter(
      text: TextSpan(children: spans),
      textDirection: TextDirection.ltr,
      maxLines: 8,
      ellipsis: '...',
    );

    textPainter.layout(maxWidth: drawWidth * 0.75); // Slightly narrower to prevent edge-touching

    // ===============================
    // POSITION
    // ===============================
    final paddingH = drawWidth * 0.03;
    final paddingV = drawWidth * 0.02; // Using width for consistent padding
    final marginX = drawWidth * 0.04;
    final marginY = drawHeight * 0.04;

    final boxWidth = textPainter.width + (paddingH * 2);
    final boxHeight = textPainter.height + (paddingV * 2);

    final dx = data.position == WatermarkPosition.bottomLeft
        ? marginX
        : drawWidth - boxWidth - marginX;

    final dy = drawHeight - boxHeight - marginY;

    final boxRect = Rect.fromLTWH(dx, dy, boxWidth, boxHeight);

    // ===============================
    // BACKGROUND CARD
    // ===============================
    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.85); // More solid for readability

    // Subtle Border
    final borderPaint = Paint()
      ..color = Colors.black.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(boxRect, const Radius.circular(8)),
      bgPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(boxRect, const Radius.circular(8)),
      borderPaint,
    );

    // ===============================
    // DRAW TEXT
    // ===============================
    textPainter.paint(canvas, Offset(dx + paddingH, dy + paddingV));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LiveOverlayPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.orientation != orientation;
  }
}