import 'dart:io';

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
}
