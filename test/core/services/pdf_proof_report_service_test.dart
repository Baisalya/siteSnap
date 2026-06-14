import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:surveycam/core/services/pdf_proof_report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('createReport writes a PDF proof report for selected photos', () async {
    final directory = await Directory.systemTemp.createTemp('surveycam_pdf_');
    addTearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    final photo = File('${directory.path}/capture.jpg');
    final image = img.Image(width: 80, height: 60);
    img.fill(image, color: img.ColorRgb8(220, 180, 40));
    await photo.writeAsBytes(img.encodeJpg(image));

    final report = await const PdfProofReportService().createReport(
      files: [photo],
      reportTitle: 'Site A Completion Proof - कार्य रिपोर्ट',
      projectName: 'Site A - परियोजना',
      photoDescriptions: {
        photo.path:
            'North wall waterproofing completed and verified. निरीक्षण पूरा हुआ। বাংলা தமிழ் عربي',
      },
      generatedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      outputDirectory: directory,
    );

    expect(report.existsSync(), isTrue);
    expect(report.path.endsWith('.pdf'), isTrue);

    final header = await report.openRead(0, 4).first;
    expect(String.fromCharCodes(header), '%PDF');
  });
}
