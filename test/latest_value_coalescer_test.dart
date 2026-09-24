import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/features/camera/application/latest_value_coalescer.dart';

void main() {
  test('keeps only the latest value while an update is in flight', () async {
    final firstUpdate = Completer<void>();
    final applied = <int>[];
    final coalescer = LatestValueCoalescer<int>();

    Future<void> apply(int value) async {
      applied.add(value);
      if (value == 1) {
        await firstUpdate.future;
      }
    }

    coalescer.submit(1, apply);
    coalescer.submit(2, apply);
    coalescer.submit(3, apply);

    expect(applied, [1]);
    expect(coalescer.isBusy, isTrue);

    firstUpdate.complete();
    await _waitUntilIdle(coalescer);

    expect(applied, [1, 3]);
  });

  test('flush drops queued history and applies one authoritative value',
      () async {
    final firstUpdate = Completer<void>();
    final applied = <int>[];
    final coalescer = LatestValueCoalescer<int>();

    Future<void> apply(int value) async {
      applied.add(value);
      if (value == 1) {
        await firstUpdate.future;
      }
    }

    coalescer.submit(1, apply);
    coalescer.submit(2, apply);
    final flush = coalescer.flush(3, apply);

    expect(applied, [1]);
    firstUpdate.complete();
    await flush;

    expect(applied, [1, 3]);
    expect(coalescer.isBusy, isFalse);
  });
}

Future<void> _waitUntilIdle<T>(LatestValueCoalescer<T> coalescer) async {
  while (coalescer.isBusy) {
    await Future<void>.delayed(Duration.zero);
  }
}
