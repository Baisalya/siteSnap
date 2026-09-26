import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/features/camera/application/camera_session_queue.dart';

void main() {
  test('switch finalization cannot overlap Stop or background disposal',
      () async {
    final queue = CameraSessionQueue();
    final finalized = Completer<void>();
    final events = <String>[];
    final switching = queue.run(() async {
      events.add('segment-stop');
      await finalized.future;
      events.add('segment-finalized');
      events.add('lens-switch');
    });
    final stop = queue.run(() async => events.add('stop-and-save'));
    final background = queue.run(() async => events.add('dispose'));
    await Future<void>.delayed(Duration.zero);
    expect(events, ['segment-stop']);
    finalized.complete();
    await Future.wait([switching, stop, background]);
    expect(events, [
      'segment-stop',
      'segment-finalized',
      'lens-switch',
      'stop-and-save',
      'dispose',
    ]);
  });

  test('failed transition does not prevent queued cleanup', () async {
    final queue = CameraSessionQueue();
    final failed = queue.run<void>(() async => throw StateError('camera lost'));
    final cleanup = queue.run(() async => 'disposed');
    await expectLater(failed, throwsStateError);
    expect(await cleanup, 'disposed');
  });
}
