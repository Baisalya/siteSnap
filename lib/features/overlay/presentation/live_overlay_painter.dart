import 'package:flutter/material.dart';
import '../domain/overlay_model.dart';

class LiveOverlayPainter extends CustomPainter {
  final OverlayData data;

  LiveOverlayPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: 14,
      shadows: const [
        Shadow(
          offset: Offset(1, 1),
          blurRadius: 3,
          color: Colors.black,
        ),
      ],
    );

    final text = '''
${data.dateTime}
Lat: ${data.lat.toStringAsFixed(5)}, Lng: ${data.lng.toStringAsFixed(5)}
Alt: ${data.altitude.toStringAsFixed(1)} m | ${data.direction}
${data.note}
''';

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout(maxWidth: size.width - 20);

    // Bottom-left positioning
    final offset = Offset(
      10,
      size.height - textPainter.height - 20,
    );

    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant LiveOverlayPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}
