import 'package:flutter/material.dart';
import '../domain/overlay_model.dart';

class LiveOverlayPainter extends CustomPainter {
  final OverlayData data;

  LiveOverlayPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width == 0 || size.height == 0) return;

    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: 16, // 🔥 slightly bigger
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

    textPainter.layout(
      maxWidth: size.width * 0.9,
    );

    // ✅ Bottom-left safe positioning
    final offset = Offset(
      16,
      size.height - textPainter.height - 24,
    );

    // 🔲 Optional background for readability
    final bgRect = Rect.fromLTWH(
      offset.dx - 8,
      offset.dy - 8,
      textPainter.width + 16,
      textPainter.height + 16,
    );

    final bgPaint = Paint()
      ..color = Colors.black.withOpacity(0.45);

    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(8)),
      bgPaint,
    );

    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant LiveOverlayPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}
