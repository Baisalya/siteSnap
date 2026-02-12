import 'package:flutter/material.dart';
import '../domain/overlay_model.dart';

class LiveOverlayPainter extends CustomPainter {
  final OverlayData data;

  LiveOverlayPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width == 0 || size.height == 0) return;

    // ===============================
    // TEXT STYLE
    // ===============================
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: size.width * 0.035, // ✅ responsive size
      height: 1.25,
      shadows: const [
        Shadow(
          offset: Offset(1.5, 1.5),
          blurRadius: 4,
          color: Colors.black,
        ),
      ],
    );

    // ===============================
    // WATERMARK TEXT
    // ===============================
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

    textPainter.layout(maxWidth: size.width * 0.9);

    // ===============================
    // ✅ RELATIVE POSITIONING (FIX)
    // Works in portrait + landscape
    // ===============================
    final marginX = size.width * 0.03;
    final marginY = size.height * 0.03;

    final offset = Offset(
      marginX,
      size.height - textPainter.height - marginY,
    );

    // ===============================
    // BACKGROUND BOX
    // ===============================
    final bgRect = Rect.fromLTWH(
      offset.dx - size.width * 0.01,
      offset.dy - size.height * 0.01,
      textPainter.width + size.width * 0.02,
      textPainter.height + size.height * 0.02,
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

    // ===============================
    // DRAW TEXT
    // ===============================
    textPainter.paint(canvas, offset);

    // ===============================
    // LOCATION WARNING (TOP LEFT)
    // ===============================
    if (data.locationWarning != null &&
        data.locationWarning!.isNotEmpty) {
      final warningPainter = TextPainter(
        text: TextSpan(
          text: data.locationWarning!,
          style: TextStyle(
            color: Colors.red,
            fontSize: size.width * 0.032,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      warningPainter.layout();

      warningPainter.paint(
        canvas,
        Offset(
          size.width * 0.03,
          size.height * 0.05,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant LiveOverlayPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}
