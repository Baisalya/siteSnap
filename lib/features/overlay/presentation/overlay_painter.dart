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
Lat: ${data.lat}, Lng: ${data.lng}
Alt: ${data.altitude}m | ${data.direction}
${data.note}
''';

  img.drawString(
    image,
    text,
    font: img.arial24, // ✅ CORRECT
    x: 20,
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
