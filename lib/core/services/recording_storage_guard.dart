import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class RecordingStorageStatus {
  final int? usableBytes;
  final int minimumRequiredBytes;

  const RecordingStorageStatus({
    required this.usableBytes,
    required this.minimumRequiredBytes,
  });

  bool get isKnown => usableBytes != null;
  bool get canStart =>
      usableBytes == null || usableBytes! >= minimumRequiredBytes;
}

/// Lightweight preflight guard for low-storage recording failures.
///
/// Unknown storage is deliberately non-blocking so non-Android platforms and
/// devices that cannot report storage continue using the camera normally.
class RecordingStorageGuard {
  static const MethodChannel _channel =
      MethodChannel('surveycam/local_environment');
  static const int minimumFreeBytes = 200 * 1024 * 1024;

  const RecordingStorageGuard._();

  static Future<RecordingStorageStatus> check() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const RecordingStorageStatus(
        usableBytes: null,
        minimumRequiredBytes: minimumFreeBytes,
      );
    }

    try {
      final bytes = await _channel.invokeMethod<int>('getUsableStorageBytes');
      return RecordingStorageStatus(
        usableBytes: bytes,
        minimumRequiredBytes: minimumFreeBytes,
      );
    } on MissingPluginException {
      return const RecordingStorageStatus(
        usableBytes: null,
        minimumRequiredBytes: minimumFreeBytes,
      );
    } on PlatformException catch (error) {
      debugPrint('Recording storage preflight unavailable: $error');
      return const RecordingStorageStatus(
        usableBytes: null,
        minimumRequiredBytes: minimumFreeBytes,
      );
    }
  }
}
