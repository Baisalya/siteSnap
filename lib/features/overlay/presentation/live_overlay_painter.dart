import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:surveycam/features/overlay/domain/overlay_model.dart';
import 'package:surveycam/features/overlay/domain/WatermarkPosition.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';
import 'package:surveycam/core/utils/overlay_utils.dart';

class LiveOverlayPainter extends CustomPainter {
  final OverlayData data;
  final DeviceOrientation orientation;
  final OverlaySettings settings;

  LiveOverlayPainter(this.data, this.orientation, {this.settings = const OverlaySettings()});

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
      color: settings.textColor,
      fontSize: baseSize * 0.032,
      fontWeight: FontWeight.w600,
      height: 1.2,
      letterSpacing: 0.2,
    );

    final warningStyle = textStyle.copyWith(color: Colors.redAccent);
    final noteStyle = textStyle.copyWith(
      fontSize: baseSize * 0.035, 
      color: settings.textColor,
      fontStyle: FontStyle.italic,
    );

    // ===============================
    // BUILD TEXT SPANS
    // ===============================
    final List<TextSpan> spans = [];

    if (settings.showDateTime && data.dateTime.isNotEmpty) {
      spans.add(TextSpan(text: "${data.dateTime}\n", style: textStyle));
    }

    if (data.locationWarning != null) {
      spans.add(TextSpan(text: "${data.locationWarning}\n", style: warningStyle));
    } else if (settings.showCoordinates) {
      final latLabel = OverlayUtils.getLabel('latitude', settings.language);
      final lonLabel = OverlayUtils.getLabel('longitude', settings.language);
      final latVal = OverlayUtils.formatCoordinate(data.latitude, true, settings.coordinateFormat);
      final lonVal = OverlayUtils.formatCoordinate(data.longitude, false, settings.coordinateFormat);
      
      spans.add(TextSpan(
        text: "$latLabel: $latVal\n$lonLabel: $lonVal\n",
        style: textStyle,
      ));
    }

    String altDirText = "";
    if (settings.showAltitude) {
      final altLabel = OverlayUtils.getLabel('altitude', settings.language);
      altDirText += "$altLabel: ${data.altitude.toStringAsFixed(1)}m  ";
    }
    if (settings.showDirection) {
      final dirLabel = OverlayUtils.getLabel('direction', settings.language);
      altDirText += "$dirLabel: ${data.direction} ${data.heading.toStringAsFixed(0)}°";
    }
    if (altDirText.isNotEmpty) {
      spans.add(TextSpan(text: "$altDirText\n", style: textStyle));
    }

    if (settings.showWeather && data.weather != null) {
      final label = OverlayUtils.getLabel('weather', settings.language);
      spans.add(TextSpan(text: "$label: ${data.weather}\n", style: textStyle));
    }

    if (settings.showHumidity && data.humidity != null) {
      final label = OverlayUtils.getLabel('humidity', settings.language);
      spans.add(TextSpan(text: "$label: ${data.humidity}\n", style: textStyle));
    }

    if (settings.showPressure && data.pressure != null) {
      final label = OverlayUtils.getLabel('pressure', settings.language);
      spans.add(TextSpan(text: "$label: ${data.pressure}\n", style: textStyle));
    }

    if (settings.showAir && data.air != null) {
      final label = OverlayUtils.getLabel('air', settings.language);
      spans.add(TextSpan(text: "$label: ${data.air}\n", style: textStyle));
    }

    if (settings.showNote && data.note.isNotEmpty) {
      spans.add(TextSpan(text: data.note, style: noteStyle));
    }

    final textPainter = TextPainter(
      text: TextSpan(children: spans),
      textDirection: TextDirection.ltr,
      maxLines: 8,
      ellipsis: '...',
    );

    textPainter.layout(maxWidth: baseSize * 0.75);

    // ===============================
    // POSITION
    // ===============================
    final paddingH = baseSize * 0.03;
    final paddingV = baseSize * 0.02;
    final marginX = baseSize * 0.04;
    final marginY = baseSize * 0.04;

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
      ..color = settings.backgroundColor.withOpacity(settings.backgroundOpacity);

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
        oldDelegate.orientation != orientation ||
        oldDelegate.settings != settings;
  }
}
