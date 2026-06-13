import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Privacy-first local diagnostics helper.
///
/// Nothing is uploaded. Use this to write local diagnostic entries that users
/// can explicitly export when reporting capture/gallery/video-processing bugs.
class LocalDiagnosticsService {
  const LocalDiagnosticsService({required this.logDirectory});

  final Directory logDirectory;

  static Future<LocalDiagnosticsService> appScoped() async {
    final docDir = await getApplicationDocumentsDirectory();
    return LocalDiagnosticsService(
      logDirectory: Directory(p.join(docDir.path, 'surveycam', 'diagnostics')),
    );
  }

  Future<File> appendEvent({
    required String event,
    required Map<String, Object?> details,
  }) async {
    if (!await logDirectory.exists()) {
      await logDirectory.create(recursive: true);
    }

    final file = File('${logDirectory.path}/sitesnap_diagnostics.jsonl');
    final payload = <String, Object?>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'event': event,
      'details': details,
    };
    await file.writeAsString('${jsonEncode(payload)}\n',
        mode: FileMode.append, flush: true);
    return file;
  }
}
