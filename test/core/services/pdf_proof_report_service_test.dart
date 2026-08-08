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
    final directory =
        await Directory.systemTemp.createTemp('surveycam_pdf_video_');
    addTearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    final video = File('${directory.path}/capture.mp4');
    await video.writeAsString('fake video content');
    final thumbnail = File('${directory.path}/video-thumbnail.jpg');
    final image = img.Image(width: 80, height: 60);
    img.fill(image, color: img.ColorRgb8(120, 40, 180));
    await thumbnail.writeAsBytes(img.encodeJpg(image));
    var thumbnailRequested = false;

    final report = await PdfProofReportService(
      videoThumbnailGenerator: (
        path, {
        required maxWidth,
        required quality,
      }) async {
        thumbnailRequested = true;
        expect(path, video.path);
        expect(maxWidth, 1280);
        expect(quality, 90);
        return thumbnail.path;
      },
    ).createReport(
      files: [video],
      reportTitle: 'Video Report',
      outputDirectory: directory,
    );

    expect(thumbnailRequested, isTrue);
    expect(report.existsSync(), isTrue);
    final header = await report.openRead(0, 4).first;
    expect(String.fromCharCodes(header), '%PDF');
  });

  test('createReport rejects unbounded capture selections before processing',
      () async {
    final files = List<File>.generate(
      PdfProofReportService.maxReportItems + 1,
      (index) => File('missing-$index.jpg'),
    );

    await expectLater(
      const PdfProofReportService().createReport(files: files),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('at most'),
        ),
      ),
    );
  });

  test('createReport bounds long user text and creates a missing output folder',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('surveycam_pdf_bounds_');
    addTearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });
    final output = Directory('${directory.path}/nested/report');
    final photo = File('${directory.path}/capture.jpg');
    final image = img.Image(width: 80, height: 60);
    img.fill(image, color: img.ColorRgb8(20, 80, 160));
    await photo.writeAsBytes(img.encodeJpg(image));

    final report = await const PdfProofReportService().createReport(
      files: [photo],
      reportTitle: List.filled(1000, 'T').join(),
      projectName: List.filled(1000, 'P').join(),
      photoDescriptions: {
        photo.path: List.filled(1000, 'Description ').join(),
      },
      generatedAt: DateTime.utc(2026, 2, 3, 4, 5, 6),
      outputDirectory: output,
    );

    expect(output.existsSync(), isTrue);
    expect(report.existsSync(), isTrue);
    expect(await report.length(), greaterThan(1000));
  });

  test('proof identity changes when report descriptions change', () async {
    final directory =
        await Directory.systemTemp.createTemp('surveycam_pdf_id_');
    addTearDown(() => directory.delete(recursive: true));
    final photo = File('${directory.path}/capture.jpg');
    final image = img.Image(width: 40, height: 40);
    await photo.writeAsBytes(img.encodeJpg(image));
    final generatedAt = DateTime.utc(2026, 3, 4, 5, 6, 7);
    const service = PdfProofReportService();

    final first = await service.createReport(
      files: [photo],
      photoDescriptions: {photo.path: 'Before repair'},
      generatedAt: generatedAt,
      outputDirectory: directory,
    );
    final second = await service.createReport(
      files: [photo],
      photoDescriptions: {photo.path: 'After repair'},
      generatedAt: generatedAt,
      outputDirectory: directory,
    );

    expect(first.path, isNot(second.path));
  });
}
