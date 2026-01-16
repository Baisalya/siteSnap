import 'dart:io';
import 'package:image_gallery_saver/image_gallery_saver.dart';

class GallerySaver {
  static Future<File> saveImage(File file) async {
    final result = await ImageGallerySaver.saveFile(
      file.path,
      name: 'SiteSnap_${DateTime.now().millisecondsSinceEpoch}',
    );

    if (result['isSuccess'] != true) {
      throw Exception('Failed to save image to gallery');
    }

    return file; // keep using original file
  }
}
