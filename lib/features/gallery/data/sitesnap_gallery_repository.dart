import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

final galleryRepositoryProvider = Provider((ref) => SurveyCamGalleryRepository());

final galleryFilesProvider = FutureProvider<List<File>>((ref) async {
  final repo = ref.watch(galleryRepositoryProvider);
  return repo.loadImages();
});

class SurveyCamGalleryRepository {
  Future<List<File>> loadImages() async {
    final List<Directory> directories = [];

    if (Platform.isAndroid) {
      // ✅ Check common Pictures and Movies folders
      directories.add(Directory('/storage/emulated/0/Pictures/surveycam'));
      directories.add(Directory('/storage/emulated/0/Pictures/survaycam'));
      directories.add(Directory('/storage/emulated/0/Movies/surveycam'));
      directories.add(Directory('/storage/emulated/0/Movies/survaycam'));
      
      // Also check standard DCIM and common camera folders
      directories.add(Directory('/storage/emulated/0/DCIM/surveycam'));
      directories.add(Directory('/storage/emulated/0/DCIM/Camera/surveycam'));
      directories.add(Directory('/storage/emulated/0/DCIM/Camera'));
    } else if (Platform.isIOS) {
      final docDir = await getApplicationDocumentsDirectory();
      directories.add(Directory('${docDir.path}/surveycam'));
      directories.add(Directory('${docDir.path}/survaycam'));
    }

    final List<File> allFiles = [];

    for (var directory in directories) {
      try {
        if (await directory.exists()) {
          final isSurveyCam = directory.path.toLowerCase().contains('surveycam') || 
                             directory.path.toLowerCase().contains('survaycam');
          
          final files = directory
              .listSync(recursive: isSurveyCam) // Recursive only for our app folders
              .whereType<File>()
              .where((file) {
            final path = file.path.toLowerCase();
            // Filter only our files if it's a general folder like DCIM/Camera
            if (!isSurveyCam) {
              final name = p.basename(path);
              if (!name.contains('SurveyCam') && !name.contains('Surveycam')) {
                return false;
              }
            }
            
            return path.endsWith('.jpg') ||
                path.endsWith('.jpeg') ||
                path.endsWith('.png') ||
                path.endsWith('.mp4') ||
                path.endsWith('.mov');
          });
          allFiles.addAll(files);
        }
      } catch (e) {
        // Silently skip
      }
    }

    // ✅ newest first across all folders
    allFiles.sort((a, b) {
      try {
        return b.lastModifiedSync().compareTo(a.lastModifiedSync());
      } catch (_) {
        return 0;
      }
    });

    return allFiles;
  }
}
