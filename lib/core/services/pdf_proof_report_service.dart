import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum ProofReportTemplate {
  standard,
  compact,
}

class PdfProofReportService {
  const PdfProofReportService();

  Future<File> createReport({
    required List<File> files,
    String? reportTitle,
    String? projectName,
    Map<String, String> photoDescriptions = const <String, String>{},
    ProofReportTemplate template = ProofReportTemplate.standard,
    DateTime? generatedAt,
    Directory? outputDirectory,
  }) async {
    final existingFiles =
        files.where((file) => file.existsSync()).toList(growable: false);
    if (existingFiles.isEmpty) {
      throw ArgumentError('No existing files were provided for PDF export.');
    }

    final generated = generatedAt ?? DateTime.now();
    final entries = <_ProofReportEntry>[];
    for (final file in existingFiles) {
      entries.add(
        await _buildEntry(
          file,
          description: photoDescriptions[file.path]?.trim() ?? '',
        ),
      );
    }
    final title = _cleanReportTitle(reportTitle);

    final proofId = _createProofId(entries, generated);
    final theme = await _loadTheme();
    final document = pw.Document(
      title: title,
      author: 'SurveyCam',
      subject: 'Field capture proof report',
      keywords: 'SurveyCam, proof, GPS, watermark, field report',
      theme: theme,
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        footer: (context) => _footer(context, proofId),
        build: (context) => [
          _header(
            reportTitle: title,
            projectName: projectName,
            generatedAt: generated,
            proofId: proofId,
            itemCount: entries.length,
            template: template,
          ),
          pw.SizedBox(height: 18),
          _reportPurposeNote(),
          pw.SizedBox(height: 16),
          if (template == ProofReportTemplate.compact)
            _compactLayout(entries)
          else
            ...entries.map(_standardEntry),
        ],
      ),
    );

    final directory = outputDirectory ?? await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(generated.toLocal());
    final output = File(p.join(directory.path, 'SurveyCam_Proof_$stamp.pdf'));
    await output.writeAsBytes(await document.save(), flush: true);
    return output;
  }

  Future<pw.ThemeData> _loadTheme() async {
    final base = pw.Font.ttf(
      await rootBundle.load('Assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('Assets/fonts/NotoSans-Bold.ttf'),
    );
    final devanagari = pw.Font.ttf(
      await rootBundle.load('Assets/fonts/NotoSansDevanagari-Regular.ttf'),
    );
    final devanagariBold = pw.Font.ttf(
      await rootBundle.load('Assets/fonts/NotoSansDevanagari-Bold.ttf'),
    );
    final regionalFallbacks = <pw.Font>[];
    for (final fontName in const [
      'NotoSansBengali',
      'NotoSansGujarati',
      'NotoSansGurmukhi',
      'NotoSansKannada',
      'NotoSansMalayalam',
      'NotoSansTamil',
      'NotoSansTelugu',
      'NotoSansArabic',
    ]) {
      regionalFallbacks.add(
        pw.Font.ttf(
          await rootBundle.load('Assets/fonts/$fontName-Regular.ttf'),
        ),
      );
    }

    return pw.ThemeData.withFont(
      base: base,
      bold: bold,
      fontFallback: [devanagari, devanagariBold, ...regionalFallbacks],
    );
  }

  String _cleanReportTitle(String? reportTitle) {
    final cleaned = reportTitle?.trim();
    if (cleaned == null || cleaned.isEmpty) {
      return 'SurveyCam Proof Report';
    }
    return cleaned;
  }

  pw.Widget _reportPurposeNote() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.amber50,
        border: pw.Border.all(color: PdfColors.amber200),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Text(
        'This report is prepared as a field proof packet. Each selected capture '
        'is shown with its visible watermark preview, file details, and a '
        'SHA-256 verification hash so teams can review the evidence and compare '
        'the exported media against the original device file when required.',
        style: const pw.TextStyle(
          color: PdfColors.grey800,
          fontSize: 10,
          lineSpacing: 2,
        ),
      ),
    );
  }

  Future<_ProofReportEntry> _buildEntry(
    File file, {
    required String description,
  }) async {
    final stat = await file.stat();
    final sha = await _sha256(file);
    return _ProofReportEntry(
      fileName: p.basename(file.path),
      path: file.path,
      sizeBytes: stat.size,
      modifiedAt: stat.modified,
      sha256: sha,
      description: description,
      previewBytes: await _previewBytes(file),
    );
  }

  Future<Uint8List?> _previewBytes(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final resized =
          decoded.width > 1400 ? img.copyResize(decoded, width: 1400) : decoded;
      return Uint8List.fromList(img.encodeJpg(resized, quality: 82));
    } catch (_) {
      return null;
    }
  }

  Future<String> _sha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  String _createProofId(List<_ProofReportEntry> entries, DateTime generatedAt) {
    final seed = jsonEncode({
      'generatedAt': generatedAt.toUtc().toIso8601String(),
      'files': entries
          .map((entry) => {
                'name': entry.fileName,
                'size': entry.sizeBytes,
                'sha256': entry.sha256,
              })
          .toList(),
    });
    return sha256.convert(utf8.encode(seed)).toString().substring(0, 16);
  }

  pw.Widget _header({
    required String reportTitle,
    required String? projectName,
    required DateTime generatedAt,
    required String proofId,
    required int itemCount,
    required ProofReportTemplate template,
  }) {
    final generatedText =
        DateFormat('dd MMM yyyy, hh:mm a').format(generatedAt.toLocal());

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey900,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            reportTitle,
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            projectName == null || projectName.isEmpty
                ? 'Project: All captures'
                : 'Project: $projectName',
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 11),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Generated: $generatedText',
            style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 10),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Proof ID: ${proofId.toUpperCase()}',
            style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 10),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Items: $itemCount | Template: ${template.name}',
            style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 10),
          ),
        ],
      ),
    );
  }

  pw.Widget _standardEntry(_ProofReportEntry entry) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _previewBox(entry, height: 290),
          pw.SizedBox(height: 10),
          _entryNarrative(entry),
          pw.SizedBox(height: 10),
          _entryDetails(entry),
        ],
      ),
    );
  }

  pw.Widget _compactLayout(List<_ProofReportEntry> entries) {
    return pw.Wrap(
      spacing: 10,
      runSpacing: 10,
      children: entries.map((entry) {
        return pw.Container(
          width: 252,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _previewBox(entry, height: 150),
              pw.SizedBox(height: 8),
              pw.Text(
                entry.fileName,
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'SHA-256: ${entry.shortHash}',
                style:
                    const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                entry.description.isEmpty
                    ? 'Included as field proof with preview and verification hash.'
                    : 'Note: ${_compactDescription(entry.description)}',
                style:
                    const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  pw.Widget _previewBox(_ProofReportEntry entry, {required double height}) {
    final preview = entry.previewBytes;
    if (preview == null) {
      return pw.Container(
        height: height,
        alignment: pw.Alignment.center,
        color: PdfColors.grey200,
        child: pw.Text(
          'Preview unavailable',
          style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
        ),
      );
    }

    return pw.Container(
      height: height,
      alignment: pw.Alignment.center,
      color: PdfColors.grey100,
      child: pw.Image(
        pw.MemoryImage(preview),
        fit: pw.BoxFit.contain,
      ),
    );
  }

  pw.Widget _entryNarrative(_ProofReportEntry entry) {
    final modified =
        DateFormat('dd MMM yyyy, hh:mm a').format(entry.modifiedAt.toLocal());
    final userDescription = entry.description.isEmpty
        ? ''
        : 'Field description: ${entry.description}\n\n';
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Text(
        '${userDescription}Capture note: ${entry.fileName} is included as a visual proof item in '
        'this SurveyCam report. The image preview above should be reviewed with '
        'the on-photo watermark details, while the file record below confirms '
        'the saved media name, last modified time ($modified), size, and '
        'verification hash for audit or client handover.',
        style: const pw.TextStyle(
          color: PdfColors.grey800,
          fontSize: 9,
          lineSpacing: 2,
        ),
      ),
    );
  }

  String _compactDescription(String description) {
    final cleaned = description.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= 92) return cleaned;
    return '${cleaned.substring(0, 89)}...';
  }

  pw.Widget _entryDetails(_ProofReportEntry entry) {
    final modified =
        DateFormat('dd MMM yyyy, hh:mm a').format(entry.modifiedAt.toLocal());
    return pw.Table(
      columnWidths: const {
        0: pw.FixedColumnWidth(86),
        1: pw.FlexColumnWidth(),
      },
      children: [
        _detailRow('File', entry.fileName),
        _detailRow('Modified', modified),
        _detailRow('Size', _formatBytes(entry.sizeBytes)),
        _detailRow('SHA-256', entry.sha256),
        _detailRow('Path', entry.path),
      ],
    );
  }

  pw.TableRow _detailRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4, right: 8),
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Text(value, style: const pw.TextStyle(fontSize: 8)),
        ),
      ],
    );
  }

  pw.Widget _footer(pw.Context context, String proofId) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'SurveyCam proof ID ${proofId.toUpperCase()}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
        pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

class _ProofReportEntry {
  const _ProofReportEntry({
    required this.fileName,
    required this.path,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.sha256,
    required this.description,
    required this.previewBytes,
  });

  final String fileName;
  final String path;
  final int sizeBytes;
  final DateTime modifiedAt;
  final String sha256;
  final String description;
  final Uint8List? previewBytes;

  String get shortHash => sha256.substring(0, 16);
}
