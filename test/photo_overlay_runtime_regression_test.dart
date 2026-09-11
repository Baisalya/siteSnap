import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:surveycam/features/overlay/domain/overlay_model.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';
import 'package:surveycam/features/overlay/presentation/overlay_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('default SurveyCam logo remains drawable across repeated photo saves',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('sitesnap_overlay_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final source = img.Image(width: 120, height: 160);
    img.fill(source, color: img.ColorRgb8(40, 80, 120));
    final sourceFile = File('${tempDir.path}/source.jpg');
    await sourceFile.writeAsBytes(img.encodeJpg(source, quality: 90));

    const data = OverlayData(
      dateTime: '2026-09-10 18:00:00',
      latitude: 20.0,
      longitude: 86.0,
      altitude: 10,
      heading: 0,
      direction: 'N',
      note: 'Regression',
    );
    const settings = OverlaySettings(
      showWeather: false,
      watermarkPresetIndex: 0,
    );

    final first = await WatermarkProcessor.drawOverlay(
      sourceFile,
      data,
      DeviceOrientation.portraitUp,
      showOverlay: false,
      showWatermark: true,
      settings: settings,
    );
    final second = await WatermarkProcessor.drawOverlay(
      sourceFile,
      data,
      DeviceOrientation.portraitUp,
      showOverlay: false,
      showWatermark: true,
      settings: settings,
    );

    expect(first, isNotEmpty);
    expect(second, isNotEmpty);
  });
}
