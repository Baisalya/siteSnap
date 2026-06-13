import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/core/services/proof_manifest_service.dart';

void main() {
  test('createManifest writes hash-backed proof json', () async {
    final dir = await Directory.systemTemp.createTemp('proof_manifest_test_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final original = File('${dir.path}/original.jpg')..writeAsStringSync('raw');
    final output = File('${dir.path}/output.jpg')
      ..writeAsStringSync('watermarked');

    final file = await const ProofManifestService().createManifest(
      originalFile: original,
      outputFile: output,
      captureMetadata: <String, Object?>{
        'lat': 20.2961,
        'lng': 85.8245,
      },
      overlaySettings: <String, Object?>{
        'timestamp': true,
        'location': true,
      },
    );

    expect(await file.exists(), isTrue);
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(json['manifestVersion'], '1');
    expect(json['originalSha256'], isA<String>());
    expect(json['outputSha256'], isA<String>());
    expect(json['originalSha256'], isNot(json['outputSha256']));
    expect(json['captureMetadata'], isA<Map>());
    expect(json['overlaySettings'], isA<Map>());
  });
}
