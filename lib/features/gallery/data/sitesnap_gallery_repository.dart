import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:surveycam/core/utils/gallery_saver.dart';

final galleryRepositoryProvider =
    Provider((ref) => SurveyCamGalleryRepository());

final galleryFilesProvider = FutureProvider.autoDispose<List<File>>((ref) async {
  final repo = ref.watch(galleryRepositoryProvider);
  // Force a fresh load when the provider is first accessed or refreshed
  return repo.loadImages(forceRefresh: true);
});

class SurveyCamGalleryRepository {
  List<File>? _cachedFiles;
  DateTime? _lastFetchTime;

  Future<List<File>> loadImages({bool forceRefresh = false}) async {
    // Return cached results only if they are very fresh (less than 2 seconds old)
    // to prevent redundant disk IO during rapid UI rebuilds.
    if (!forceRefresh && _cachedFiles != null && _lastFetchTime != null) {
      if (DateTime.now().difference(_lastFetchTime!) < const Duration(seconds: 2)) {
        return _cachedFiles!;
      }
    }

    final List<Directory> directories = [];
    directories.add(await GallerySaver.localAlbumDirectory());

    if (Platform.isAndroid) {
      // ✅ Check common Pictures and Movies folders
      directories.add(Directory('/storage/emulated/0/Pictures/surveycam'));
      directories.add(Directory('/storage/emulated/0/Movies/surveycam'));

      // Also check standard DCIM and common camera folders
      directories.add(Directory('/storage/emulated/0/DCIM/surveycam'));
      directories.add(Directory('/storage/emulated/0/DCIM/Camera/surveycam'));
    } else if (Platform.isIOS) {
      final docDir = await getApplicationDocumentsDirectory();
      directories.add(Directory('${docDir.path}/surveycam'));
    }

    final Map<String, File> allFilesByName = {};

    // Parallelize directory listing
    final results = await Future.wait(directories.map((directory) async {
      try {
        if (await directory.exists()) {
          final isSurveyCam = directory.path.toLowerCase().contains('surveycam');

          final List<File> files = [];
          // Using listSync for faster processing if the directory exists
          final List<FileSystemEntity> entities = directory.listSync(recursive: isSurveyCam);
          
          for (var entity in entities) {
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
    final fileWithDates = await Future.wait(allFilesByName.values.map((file) async {
      try {
        final date = await file.lastModified();
        return _FileWithDate(file, date);
      } catch (_) {
        return _FileWithDate(file, DateTime(1970));
      }
    }));

    fileWithDates.sort((a, b) => b.date.compareTo(a.date));

    final sortedList = fileWithDates.map((fd) => fd.file).toList();
    _cachedFiles = sortedList;
    _lastFetchTime = DateTime.now();
    
    return sortedList;
  }
}

class _FileWithDate {
  final File file;
  final DateTime date;
  _FileWithDate(this.file, this.date);
}
