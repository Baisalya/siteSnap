import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:surveycam/core/utils/gallery_saver.dart';

final galleryRepositoryProvider =
    Provider((ref) => SurveyCamGalleryRepository());

final galleryFilesProvider = FutureProvider<List<File>>((ref) async {
  final repo = ref.watch(galleryRepositoryProvider);
  return repo.loadImages();
});

class SurveyCamGalleryRepository {
  Future<List<File>> loadImages() async {
    final List<Directory> directories = [];
    directories.add(await GallerySaver.localAlbumDirectory());

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

    final Map<String, File> allFilesByName = {};

    // Parallelize directory listing
    final results = await Future.wait(directories.map((directory) async {
      try {
        if (await directory.exists()) {
          final isSurveyCam =
              directory.path.toLowerCase().contains('surveycam') ||
                  directory.path.toLowerCase().contains('survaycam');

          final List<File> files = [];
          await for (var entity in directory.list(recursive: isSurveyCam)) {
            if (entity is File) {
              final path = entity.path.toLowerCase();
              if (!isSurveyCam) {
                final name = p.basename(path);
                if (!name.contains('surveycam')) {
                  continue;
                }
              }

              if (path.endsWith('.jpg') ||
                  path.endsWith('.jpeg') ||
                  path.endsWith('.png') ||
                  path.endsWith('.mp4') ||
                  path.endsWith('.mov')) {
                files.add(entity);
              }
            }
          }
          return files;
        }
      } catch (e) {
        // Silently skip
      }
      return <File>[];
    }));

    for (var files in results) {
      for (final file in files) {
        allFilesByName[p.basename(file.path).toLowerCase()] = file;
      }
    }

    // ✅ newest first across all folders - use async lastModified for sorting
    final fileWithDates =
        await Future.wait(allFilesByName.values.map((file) async {
      try {
        final date = await file.lastModified();
        return _FileWithDate(file, date);
      } catch (_) {
        return _FileWithDate(file, DateTime(1970));
      }
    }));

    fileWithDates.sort((a, b) => b.date.compareTo(a.date));

    return fileWithDates.map((fd) => fd.file).toList();
  }
}

class _FileWithDate {
  final File file;
  final DateTime date;
  _FileWithDate(this.file, this.date);
}
