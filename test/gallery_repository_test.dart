import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/features/gallery/data/sitesnap_gallery_repository.dart';

void main() {
  test('gallery cache inserts new captures at the front', () {
    final repo = SurveyCamGalleryRepository();
    final first = File('first.jpg');
    final second = File('second.jpg');

    repo.upsertFile(first);
    repo.upsertFile(second);

    expect(repo.cachedFiles?.map((file) => file.path), [
      second.path,
      first.path,
    ]);
  });

  test('gallery cache replaces temp capture with saved file', () {
    final repo = SurveyCamGalleryRepository();
    final temp = File('temp_capture.jpg');
    final saved = File('SurveyCam_saved.jpg');

    repo.upsertFile(temp);
    repo.upsertFile(saved, replace: temp);

    expect(repo.cachedFiles?.map((file) => file.path), [saved.path]);
  });

  test('gallery processing state tracks raw to processed image swap', () {
    final notifier = GalleryProcessingNotifier();
    final raw = File('raw_capture.jpg');
    final processed = File('SurveyCam_processed.jpg');
    final states = <Map<String, GalleryProcessingItem>>[];
    final removeListener = notifier.addListener(
      states.add,
      fireImmediately: true,
    );

    notifier.start(raw);

    expect(states.last[raw.path]?.isProcessing, isTrue);

    notifier.complete(raw, processed);

    expect(states.last[raw.path]?.isComplete, isTrue);
    expect(states.last[raw.path]?.processedFile?.path, processed.path);

    removeListener();
  });

  test(
      'gallery load prefers local duplicate and includes MediaStore-only files',
      () async {
    final root = await Directory.systemTemp.createTemp('surveycam_gallery_');
    try {
      final localDir = Directory(p.join(root.path, 'surveycam'));
      final mediaDir = Directory(p.join(root.path, 'media'));
      await localDir.create(recursive: true);
      await mediaDir.create(recursive: true);

      final localCopy = File(p.join(localDir.path, 'SurveyCam_same.jpg'));
      final mediaDuplicate = File(p.join(mediaDir.path, 'SurveyCam_same.jpg'));
      final mediaOnly = File(p.join(mediaDir.path, 'SurveyCam_old.jpg'));
      await localCopy.writeAsBytes([1]);
      await mediaDuplicate.writeAsBytes([2]);
      await mediaOnly.writeAsBytes([3]);

      final repo = SurveyCamGalleryRepository(
        localAlbumDirectory: () async => localDir,
        mediaStoreFiles: () async => [mediaDuplicate, mediaOnly],
        isAndroid: true,
        isIOS: false,
      );

      final files = await repo.loadImages(forceRefresh: true);
      final paths = files.map((file) => file.path).toList();

      expect(paths, contains(localCopy.path));
      expect(paths, isNot(contains(mediaDuplicate.path)));
      expect(paths, contains(mediaOnly.path));
    } finally {
      await root.delete(recursive: true);
    }
  });
}
