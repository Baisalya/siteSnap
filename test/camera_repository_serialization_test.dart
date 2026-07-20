import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/features/camera/data/camera_repository_impl.dart';

void main() {
  group('CameraRepositoryImpl operation serialization', () {
    test('does not overlap native camera operations', () async {
      final repository = CameraRepositoryImpl();
      final releaseFirst = Completer<void>();
      final events = <String>[];

      final first = repository.runExclusive(() async {
        events.add('first-start');
        await releaseFirst.future;
        events.add('first-end');
      });
      final second = repository.runExclusive(() async {
        events.add('second-start');
        events.add('second-end');
      });

      await Future<void>.delayed(Duration.zero);
      expect(events, <String>['first-start']);

      releaseFirst.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(
        events,
        <String>['first-start', 'first-end', 'second-start', 'second-end'],
      );
    });

    test('continues after a failed operation', () async {
      final repository = CameraRepositoryImpl();
      final events = <String>[];

      await expectLater(
        repository.runExclusive<void>(() async {
          events.add('failed');
          throw StateError('camera command failed');
        }),
        throwsStateError,
      );

      await repository.runExclusive(() async {
        events.add('recovered');
      });

      expect(events, <String>['failed', 'recovered']);
    });
  });
}
