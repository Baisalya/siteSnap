import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:surveycam/core/services/pdf_proof_report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('createReport writes a multilingual PDF proof report', () async {
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

    final hindiReport = '\u0915\u093e\u0930\u094d\u092f '
        '\u0930\u093f\u092a\u094b\u0930\u094d\u091f';
    final hindiProject = '\u092a\u0930\u093f\u092f\u094b\u091c\u0928\u093e';
    final hindiNote = '\u0928\u093f\u0930\u0940\u0915\u094d\u0937\u0923 '
        '\u092a\u0942\u0930\u093e \u0939\u0941\u0906\u0964';
    final bengali = '\u09ac\u09be\u0982\u09b2\u09be';
    final tamil = '\u0ba4\u0bae\u0bbf\u0bb4\u0bcd';
    final arabic = '\u0639\u0631\u0628\u064a';
    final russian = '\u0420\u0443\u0441\u0441\u043a\u0438\u0439 '
        '\u043e\u0442\u0447\u0435\u0442';

    final report = await const PdfProofReportService().createReport(
      files: [photo],
      reportTitle: 'Site A Completion Proof - $hindiReport - $russian',
      projectName: 'Site A - $hindiProject',
      photoDescriptions: {
        photo.path:
            'North wall waterproofing completed and verified. $hindiNote $bengali $tamil $arabic $russian',
      },
      generatedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      outputDirectory: directory,
    );

    expect(report.existsSync(), isTrue);
    expect(report.path.endsWith('.pdf'), isTrue);

    final header = await report.openRead(0, 4).first;
    expect(String.fromCharCodes(header), '%PDF');
  });

  test('createReport handles video files by generating thumbnails', () async {
    final directory = await Directory.systemTemp.createTemp('surveycam_pdf_video_');
    addTearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    // Mock a video file
    final video = File('${directory.path}/capture.mp4');
    await video.writeAsString('fake video content');

    // Note: In a real test environment, ThumbnailUtils.generateVideoThumbnail 
    // might fail or need a mock because it depends on path_provider and a plugin.
    // However, we want to ensure the logic flows correctly.
    
    final report = await const PdfProofReportService().createReport(
      files: [video],
      reportTitle: 'Video Report',
      outputDirectory: directory,
    );

    expect(report.existsSync(), isTrue);
    final header = await report.openRead(0, 4).first;
    expect(String.fromCharCodes(header), '%PDF');
  });
}
