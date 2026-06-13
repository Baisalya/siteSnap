import 'dart:io';

import 'package:flutter/foundation.dart';

import 'local_diagnostics_service.dart';
import 'proof_manifest_service.dart';

class MediaAuditService {
  const MediaAuditService._();

  static Future<void> recordImageSave({
    required File originalFile,
    required File outputFile,
    required Map<String, Object?> overlayData,
    required Map<String, Object?> overlaySettings,
    required String orientation,
    required bool showOverlay,
    required bool showWatermark,
    required bool mirror,
    String? jobId,
  }) async {
    final captureMetadata = <String, Object?>{
      'type': 'image',
      'jobId': jobId,
      'orientation': orientation,
      'showOverlay': showOverlay,
      'showWatermark': showWatermark,
      'mirror': mirror,
      'overlayData': overlayData,
    };

    await _writeProofAndDiagnostic(
      event: 'image_saved',
      originalFile: originalFile,
      outputFile: outputFile,
      captureMetadata: captureMetadata,
      overlaySettings: overlaySettings,
    );
  }

  static Future<void> recordVideoSave({
    required List<File> sourceFiles,
    required File outputFile,
    required List<Map<String, dynamic>> overlayHistory,
    required int durationMs,
    required String jobId,
    required bool savedWithoutOverlay,
  }) async {
    final firstSource = sourceFiles.isEmpty ? null : sourceFiles.first;
    final originalFile = firstSource != null && await firstSource.exists()
        ? firstSource
        : outputFile;
    final captureMetadata = <String, Object?>{
      'type': 'video',
      'jobId': jobId,
      'durationMs': durationMs,
      'segmentCount': sourceFiles.length,
      'savedWithoutOverlay': savedWithoutOverlay,
      'sourceFileNames':
          sourceFiles.map((file) => file.uri.pathSegments.last).toList(),
      'overlayHistory': overlayHistory,
    };

    await _writeProofAndDiagnostic(
      event:
          savedWithoutOverlay ? 'video_saved_without_overlay' : 'video_saved',
      originalFile: originalFile,
      outputFile: outputFile,
      captureMetadata: captureMetadata,
      overlaySettings: const <String, Object?>{},
    );
  }

  static Future<void> recordFailure({
    required String event,
    required Object error,
    Map<String, Object?> details = const <String, Object?>{},
  }) async {
    try {
      final diagnostics = await LocalDiagnosticsService.appScoped();
      await diagnostics.appendEvent(
        event: event,
        details: {
          ...details,
          'error': error.toString(),
        },
      );
    } catch (diagnosticError) {
      debugPrint('Diagnostic write failed: $diagnosticError');
    }
  }

  static Future<void> _writeProofAndDiagnostic({
    required String event,
    required File originalFile,
    required File outputFile,
    required Map<String, Object?> captureMetadata,
    required Map<String, Object?> overlaySettings,
  }) async {
    try {
      final manifest = await const ProofManifestService().createManifest(
        originalFile: originalFile,
        outputFile: outputFile,
        captureMetadata: captureMetadata,
        overlaySettings: overlaySettings,
      );

      final diagnostics = await LocalDiagnosticsService.appScoped();
      await diagnostics.appendEvent(
        event: event,
        details: {
          'outputPath': outputFile.path,
          'proofManifestPath': manifest.path,
        },
      );
    } catch (error) {
      await recordFailure(
        event: '${event}_audit_failed',
        error: error,
        details: {'outputPath': outputFile.path},
      );
    }
  }
}
