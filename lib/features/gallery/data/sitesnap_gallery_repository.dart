import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:surveycam/core/services/surveycam_media_store_service.dart';
import 'package:surveycam/core/utils/gallery_saver.dart';
import 'package:surveycam/features/projects/presentation/project_provider.dart';

final galleryRepositoryProvider =
    Provider((ref) => SurveyCamGalleryRepository());

final galleryFilesProvider =
    StateNotifierProvider<GalleryFilesNotifier, AsyncValue<List<File>>>((ref) {
  final repo = ref.watch(galleryRepositoryProvider);
  final notifier = GalleryFilesNotifier(repo);
  notifier.ensureLoaded();
  return notifier;
});

final filteredGalleryFilesProvider = Provider<List<File>>((ref) {
  final galleryAsync = ref.watch(galleryFilesProvider);
  final projectController = ref.watch(projectProvider.notifier);

  return galleryAsync.maybeWhen(
    data: (images) => projectController.filterFilesForActiveProject(images),
    loading: () {
      final cached =
          ref.read(galleryRepositoryProvider).cachedFiles ?? const <File>[];
      return projectController.filterFilesForActiveProject(cached);
    },
    orElse: () => const <File>[],
  );
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

    // Only show full-screen loading if we don't have data already
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
  SurveyCamGalleryRepository({
    Future<Directory> Function()? localAlbumDirectory,
    Future<List<File>> Function()? mediaStoreFiles,
    bool? isAndroid,
    bool? isIOS,
  })  : _localAlbumDirectory =
            localAlbumDirectory ?? GallerySaver.localAlbumDirectory,
        _mediaStoreFiles =
            mediaStoreFiles ?? SurveyCamMediaStoreService.listSurveyCamMedia,
        _isAndroid = isAndroid ?? Platform.isAndroid,
        _isIOS = isIOS ?? Platform.isIOS;

  List<File>? _cachedFiles;
  DateTime? _lastFetchTime;
  final Map<String, File> _optimisticFilesByPath = {};
  final Future<Directory> Function() _localAlbumDirectory;
  final Future<List<File>> Function() _mediaStoreFiles;
  final bool _isAndroid;
  final bool _isIOS;

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

  bool _isSupportedMediaFile(File file, {required bool isSurveyCamDirectory}) {
    final path = file.path.toLowerCase();
    if (!isSurveyCamDirectory) {
      final name = p.basename(path);
      if (!name.contains('surveycam')) {
        return false;
      }
    }

    return path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.mp4') ||
        path.endsWith('.mov');
  }

  Future<List<File>> _listFilesInDirectory(Directory directory) async {
    try {
      if (!await directory.exists()) return const <File>[];

      final isSurveyCamDirectory =
          directory.path.toLowerCase().contains('surveycam');
      final files = <File>[];
      await for (final entity in directory.list(
        recursive: isSurveyCamDirectory,
        followLinks: false,
      )) {
        if (entity is File &&
            _isSupportedMediaFile(
              entity,
              isSurveyCamDirectory: isSurveyCamDirectory,
            )) {
          files.add(entity);
        }
      }
      return files;
    } catch (_) {
      return const <File>[];
    }
  }

  Future<List<File>> loadImages({bool forceRefresh = false}) async {
    // Return cached results if they are fresh (less than 60 seconds old)
    // This prevents redundant disk IO during frequent navigation.
    if (!forceRefresh && _cachedFiles != null && _lastFetchTime != null) {
      if (DateTime.now().difference(_lastFetchTime!) <
          const Duration(seconds: 60)) {
        return _cachedFiles!;
      }
    }

    final List<Directory> directories = [];
    directories.add(await _localAlbumDirectory());

    if (_isAndroid) {
      // ✅ Check common Pictures and Movies folders
      directories.add(Directory('/storage/emulated/0/Pictures/surveycam'));
      directories.add(Directory('/storage/emulated/0/Movies/surveycam'));

      // Also check standard DCIM and common camera folders
      directories.add(Directory('/storage/emulated/0/DCIM/surveycam'));
      directories.add(Directory('/storage/emulated/0/DCIM/Camera/surveycam'));
    } else if (_isIOS) {
      final docDir = await getApplicationDocumentsDirectory();
      directories.add(Directory('${docDir.path}/surveycam'));
    }

    final Map<String, File> allFilesByName = {};

    final results = await Future.wait(
      directories.map(_listFilesInDirectory),
    );

    for (var files in results) {
      for (final file in files) {
        allFilesByName.putIfAbsent(
          p.basename(file.path).toLowerCase(),
          () => file,
        );
      }
    }

    if (_isAndroid) {
      for (final file in await _mediaStoreFiles()) {
        allFilesByName.putIfAbsent(
          p.basename(file.path).toLowerCase(),
          () => file,
        );
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
