import 'dart:io';
import 'package:image/image.dart' as img;
import '../domain/overlay_model.dart';

Future<File> drawOverlay(File file, OverlayData data) async {
  final bytes = await file.readAsBytes();
  final image = img.decodeImage(bytes);

  if (image == null) {
    throw Exception('Failed to decode image');
  }

  final text = '''
${data.dateTime}
Lat: ${data.lat.toStringAsFixed(5)}, Lng: ${data.lng.toStringAsFixed(5)}
Alt: ${data.altitude.toStringAsFixed(1)} m | ${data.direction}
${data.note}
''';

  // 🔲 Semi-transparent background (bottom bar)
  img.fillRect(
    image,
    x1: 0,
    y1: image.height - 180,
    x2: image.width,
    y2: image.height,
    color: img.ColorRgba8(0, 0, 0, 140),
  );

  // 📝 Overlay text (watermark)
  img.drawString(
    image,
    text,
    font: img.arial24,
    x: 16,
    y: image.height - 160,
    color: img.ColorRgb8(255, 255, 255),
  );

  final outFile =
  File(file.path.replaceFirst('.jpg', '_overlay.jpg'));

  await outFile.writeAsBytes(
    img.encodeJpg(image, quality: 95),
  );

  return outFile;
}
