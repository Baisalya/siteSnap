import 'dart:io';
import 'package:path_provider/path_provider.dart';

class SiteSnapGalleryRepository {
  Future<List<File>> loadImages() async {
    Directory? directory;

    if (Platform.isAndroid) {
      // ✅ ONLY SiteSnap folder
      directory =
          Directory('/storage/emulated/0/Pictures/SiteSnap');
    } else if (Platform.isIOS) {
      // ✅ iOS app documents folder
      final docDir = await getApplicationDocumentsDirectory();
      directory = Directory('${docDir.path}/SiteSnap');
    }

    if (directory == null || !await directory.exists()) {
      return [];
    }

    final files = directory
        .listSync(recursive: false)
        .whereType<File>()
        .where((file) {
      final path = file.path.toLowerCase();
      return path.endsWith('.jpg') ||
          path.endsWith('.jpeg') ||
          path.endsWith('.png');
    })
        .toList();

    // ✅ newest first
    files.sort(
          (a, b) =>
          b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );

    return files;
  }
}
