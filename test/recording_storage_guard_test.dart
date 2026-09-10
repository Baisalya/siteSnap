import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/core/services/recording_storage_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('low Android storage blocks recording preflight', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('surveycam/local_environment');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getUsableStorageBytes') return 50 * 1024 * 1024;
      return null;
    });

    try {
      final status = await RecordingStorageGuard.check();
      expect(status.isKnown, isTrue);
      expect(status.canStart, isFalse);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('unknown storage remains non-blocking', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('surveycam/local_environment');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    try {
      final status = await RecordingStorageGuard.check();
      expect(status.isKnown, isFalse);
      expect(status.canStart, isTrue);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
