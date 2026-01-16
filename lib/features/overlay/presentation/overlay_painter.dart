import 'dart:io';
import 'package:image/image.dart' as img;
import '../domain/overlay_model.dart';

Future<File> drawOverlay(File file, OverlayData data) async {
  final bytes = await file.readAsBytes();
  var image = img.decodeImage(bytes);
  if (image == null) throw Exception('Decode failed');

  // ✅ Fix EXIF orientation
  image = img.bakeOrientation(image);

  final bool isLandscape = image.width > image.height;

  // 🔥 BIGGER, INTENTIONAL SIZES
  final int padding = isLandscape ? 40 : 32;
  final int boxHeight = isLandscape ? 260 : 300;
  final int boxWidth =
  isLandscape ? (image.width * 0.55).toInt() : image.width;

  final int startX = 0;
  final int startY = image.height - boxHeight;

  final text = '''
${data.dateTime}
Lat: ${data.lat.toStringAsFixed(5)}, Lng: ${data.lng.toStringAsFixed(5)}
Alt: ${data.altitude.toStringAsFixed(1)} m | ${data.direction}
${data.note}
''';

  // 🔲 Background box
  img.fillRect(
    image,
    x1: startX,
    y1: startY,
    x2: startX + boxWidth,
    y2: image.height,
    color: img.ColorRgba8(0, 0, 0, 170),
  );

  // 📝 Bigger readable text
  img.drawString(
    image,
    text,
    font: img.arial48, // 🔥 BIGGER FONT
    x: startX + padding,
    y: startY + padding,
    color: img.ColorRgb8(255, 255, 255),
  );

  final outFile =
  File(file.path.replaceFirst('.jpg', '_overlay.jpg'));

  await outFile.writeAsBytes(
    img.encodeJpg(image, quality: 100),
  );

  return outFile;
}
