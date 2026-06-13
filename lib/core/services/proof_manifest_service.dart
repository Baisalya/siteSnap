import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Creates tamper-evident local metadata next to proof captures.
///
/// This does not make a photo impossible to fake, but it gives users and teams
/// a verifiable manifest containing file hashes, capture metadata, overlay
/// settings, and app version.
class ProofManifestService {
  const ProofManifestService();

  Future<File> createManifest({
    required File originalFile,
    required File outputFile,
    required Map<String, Object?> captureMetadata,
    required Map<String, Object?> overlaySettings,
    String appName = 'SurveyCam',
    String manifestVersion = '1',
  }) async {
    final manifest = <String, Object?>{
      'manifestVersion': manifestVersion,
      'appName': appName,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'originalFileName': originalFile.uri.pathSegments.last,
      'outputFileName': outputFile.uri.pathSegments.last,
      'originalSha256': await _sha256(originalFile),
      'outputSha256': await _sha256(outputFile),
      'captureMetadata': captureMetadata,
      'overlaySettings': overlaySettings,
    };

    final manifestFile = File('${outputFile.path}.proof.json');
    const encoder = JsonEncoder.withIndent('  ');
    await manifestFile.writeAsString(encoder.convert(manifest), flush: true);
    return manifestFile;
  }

  Future<String> _sha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
