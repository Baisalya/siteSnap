import 'dart:io';

import 'package:flutter/services.dart';

class SurveyCamMediaStoreService {
  const SurveyCamMediaStoreService._();

  static const MethodChannel _channel =
      MethodChannel('surveycam/local_environment');

  static Future<List<File>> listSurveyCamMedia() async {
    if (!Platform.isAndroid) return const <File>[];

    try {
      final rows = await _channel
          .invokeListMethod<Map<dynamic, dynamic>>('listSurveyCamMedia');
      if (rows == null || rows.isEmpty) return const <File>[];

      final files = <File>[];
      for (final row in rows) {
        final path = row['path'] as String?;
        if (path == null || path.isEmpty) continue;

        final file = File(path);
        if (await file.exists()) {
          files.add(file);
        }
      }
      return files;
    } catch (_) {
      return const <File>[];
    }
  }
}
