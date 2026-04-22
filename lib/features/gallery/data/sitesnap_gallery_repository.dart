import 'dart:io';
import 'package:path_provider/path_provider.dart';

class survaycamGalleryRepository {
  Future<List<File>> loadImages() async {
    final List<Directory> directories = [];

    if (Platform.isAndroid) {
      // ✅ Check both "surveycam" and "survaycam" folders
      directories.add(Directory('/storage/emulated/0/Pictures/surveycam'));
      directories.add(Directory('/storage/emulated/0/Pictures/survaycam'));
    } else if (Platform.isIOS) {
      // ✅ iOS app documents folder
      final docDir = await getApplicationDocumentsDirectory();
      directories.add(Directory('${docDir.path}/surveycam'));
      directories.add(Directory('${docDir.path}/survaycam'));
    }

    final List<File> allFiles = [];

    for (var directory in directories) {
      if (await directory.exists()) {
        final files = directory
            .listSync(recursive: false)
            .whereType<File>()
            .where((file) {
          final path = file.path.toLowerCase();
          return path.endsWith('.jpg') ||
              path.endsWith('.jpeg') ||
              path.endsWith('.png');
        });
        allFiles.addAll(files);
      }
    }

    // ✅ newest first across all folders
    allFiles.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );

    return allFiles;
  }
}
