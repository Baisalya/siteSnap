import 'dart:io';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path_provider/path_provider.dart';

class GallerySaver {
  static Future<File> saveImage(File file) async {
    late File savedFile;

    if (Platform.isAndroid) {
      // ✅ Public Pictures/SiteSnap folder
      final directory =
      Directory('/storage/emulated/0/Pictures/SiteSnap');

      // Create folder if not exists
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }

      final newPath =
          '${directory.path}/SiteSnap_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Copy file to SiteSnap folder
      savedFile = await file.copy(newPath);

      // ✅ Notify Android gallery
      await ImageGallerySaver.saveFile(savedFile.path);
    } else {
      // ✅ iOS save directly to Photos
      final result = await ImageGallerySaver.saveFile(
        file.path,
        name: "SiteSnap_${DateTime.now().millisecondsSinceEpoch}",
      );

      if (result == null || result['isSuccess'] != true) {
        throw Exception("Failed to save image");
      }

      savedFile = file;
    }

    return savedFile;
  }
}
