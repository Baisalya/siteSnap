import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:surveycam/core/utils/gallery_saver.dart';

final galleryRepositoryProvider =
    Provider((ref) => SurveyCamGalleryRepository());

final galleryFilesProvider =
    StateNotifierProvider<GalleryFilesNotifier, AsyncValue<List<File>>>((ref) {
  final repo = ref.watch(galleryRepositoryProvider);
  final notifier = GalleryFilesNotifier(repo);
  notifier.ensureLoaded();
  return notifier;
});

final galleryProcessingProvider = StateNotifierProvider<
    GalleryProcessingNotifier, Map<String, GalleryProcessingItem>>((ref) {
  return GalleryProcessingNotifier();
});

class GalleryProcessingItem {
  final File originalFile;
  final File? processedFile;
  final bool failed;

  const GalleryProcessingItem({
    required this.originalFile,
    this.processedFile,
    this.failed = false,
  });

  bool get isComplete => processedFile != null;
  bool get isProcessing => !isComplete && !failed;

  GalleryProcessingItem copyWith({
    File? processedFile,
    bool? failed,
  }) {
    return GalleryProcessingItem(
      originalFile: originalFile,
      processedFile: processedFile ?? this.processedFile,
      failed: failed ?? this.failed,
    );
  }
}

class GalleryProcessingNotifier
    extends StateNotifier<Map<String, GalleryProcessingItem>> {
  GalleryProcessingNotifier() : super(const {});

  void start(File original) {
    state = {
      ...state,
      original.path: GalleryProcessingItem(originalFile: original),
    };
  }

  void complete(File original, File processed) {
    final existing =
        state[original.path] ?? GalleryProcessingItem(originalFile: original);
    state = {
      ...state,
      original.path: existing.copyWith(
        processedFile: processed,
        failed: false,
      ),
    };
  }

  void fail(File original) {
    final existing =
        state[original.path] ?? GalleryProcessingItem(originalFile: original);
    state = {
      ...state,
      original.path: existing.copyWith(failed: true),
    };
  }
}

class GalleryFilesNotifier extends StateNotifier<AsyncValue<List<File>>> {
  GalleryFilesNotifier(this._repo)
      : super(_repo.cachedFiles == null
            ? const AsyncValue.loading()
            : AsyncValue.data(_repo.cachedFiles!));

  final SurveyCamGalleryRepository _repo;
  Future<void>? _loadFuture;

  Future<void> ensureLoaded({bool forceRefresh = false}) {
    if (!forceRefresh && state.hasValue) {
      return Future.value();
    }

    final cached = _repo.cachedFiles;
    if (!forceRefresh && cached != null) {
      state = AsyncValue.data(cached);
      return Future.value();
    }

    return _load(forceRefresh: forceRefresh);
  }

  Future<void> refresh() => _load(forceRefresh: true);

  void showFileImmediately(File file, {File? replace}) {
    _repo.upsertFile(file, replace: replace);
    state = AsyncValue.data(_repo.cachedFiles ?? [file]);
  }

  Future<void> _load({required bool forceRefresh}) {
    if (_loadFuture != null) {
      return _loadFuture!;
    }

    if (!state.hasValue) {
      state = const AsyncValue.loading();
    }

    _loadFuture = _repo.loadImages(forceRefresh: forceRefresh).then((files) {
      if (!mounted) return;
      state = AsyncValue.data(files);
    }).catchError((Object error, StackTrace stackTrace) {
      if (!mounted) return;
      final cached = _repo.cachedFiles;
      if (cached != null) {
        state = AsyncValue.data(cached);
        return;
      }
      state = AsyncValue.error(error, stackTrace);
    }).whenComplete(() {
      _loadFuture = null;
    });

    return _loadFuture!;
  }
}

class SurveyCamGalleryRepository {
  List<File>? _cachedFiles;
  DateTime? _lastFetchTime;
  final Map<String, File> _optimisticFilesByPath = {};

  List<File>? get cachedFiles =>
      _cachedFiles == null ? null : List<File>.unmodifiable(_cachedFiles!);

  void upsertFile(File file, {File? replace}) {
    if (replace != null) {
      _optimisticFilesByPath.remove(replace.path);
    }
    _optimisticFilesByPath[file.path] = file;

    final replacePath = replace?.path;
    final baseFiles = (_cachedFiles ?? const <File>[])
        .where((existing) => existing.path != replacePath);
    final files = _mergeOptimisticFiles(baseFiles);
    _cachedFiles = files;
    _lastFetchTime = DateTime.now();
  }

  List<File> _mergeOptimisticFiles(Iterable<File> files) {
    final merged = <File>[];
    final seenPaths = <String>{};

    for (final file in _optimisticFilesByPath.values.toList().reversed) {
      merged.add(file);
      seenPaths.add(file.path);
    }

    for (final file in files) {
      if (seenPaths.add(file.path)) {
        merged.add(file);
      }
    }

    return merged;
  }

  Future<List<File>> loadImages({bool forceRefresh = false}) async {
    // Return cached results only if they are very fresh (less than 2 seconds old)
    // to prevent redundant disk IO during rapid UI rebuilds.
    if (!forceRefresh && _cachedFiles != null && _lastFetchTime != null) {
      if (DateTime.now().difference(_lastFetchTime!) <
          const Duration(seconds: 2)) {
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
          final isSurveyCam =
              directory.path.toLowerCase().contains('surveycam');

          final List<File> files = [];
          // Using listSync for faster processing if the directory exists
          final List<FileSystemEntity> entities =
              directory.listSync(recursive: isSurveyCam);

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
    for (final file in _optimisticFilesByPath.values) {
      if (await file.exists()) {
        allFilesByName[p.basename(file.path).toLowerCase()] = file;
      }
    }

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
