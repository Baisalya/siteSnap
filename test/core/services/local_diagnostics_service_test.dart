import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/core/services/local_diagnostics_service.dart';

void main() {
  test('appendEvent writes local JSONL diagnostic entry', () async {
    final dir = await Directory.systemTemp.createTemp('local_diag_test_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final file = await LocalDiagnosticsService(logDirectory: dir).appendEvent(
      event: 'video_processing_failed',
      details: <String, Object?>{
        'jobId': 'job_1',
        'reason': 'fake error',
      },
    );

    expect(await file.exists(), isTrue);
    final lines = await file.readAsLines();
    expect(lines, hasLength(1));
    final payload = jsonDecode(lines.single) as Map<String, dynamic>;
    expect(payload['event'], 'video_processing_failed');
    expect(payload['details'], isA<Map>());
  });
}
