import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/features/overlay/domain/WatermarkPosition.dart';
import 'package:surveycam/features/overlay/domain/overlay_model.dart';
import 'package:surveycam/features/overlay/domain/overlay_render_snapshot.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';
import 'package:surveycam/features/overlay/presentation/video_watermark_processor.dart';

const _settings = OverlaySettings();

OverlayRenderSnapshot _snapshot(
  DeviceOrientation orientation, {
  WatermarkPosition position = WatermarkPosition.bottomLeft,
}) {
  return OverlayRenderSnapshot(
    data: OverlayData(
      dateTime: '10/09/2026 16:45:43',
      latitude: 20.685871,
      longitude: 86.647844,
      altitude: -61,
      heading: 307,
      direction: 'NW',
      note: 'Atomic layout',
      position: position,
    ),
    settings: _settings,
    orientation: orientation,
  );
}

Future<Uint8List> _rawRgba(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    final frame = await codec.getNextFrame();
    try {
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

double? _visiblePixelCentroidX(
  Uint8List rgba, {
  required int width,
  required int top,
  required int bottom,
}) {
  var weightedX = 0.0;
  var weight = 0.0;
  for (var y = top; y < bottom; y++) {
    for (var x = 0; x < width; x++) {
      final alpha = rgba[((y * width) + x) * 4 + 3];
      if (alpha <= 12) continue;
      weightedX += x * alpha;
      weight += alpha;
    }
  }
  return weight == 0 ? null : weightedX / weight;
}

bool _hasVisiblePixel(
  Uint8List rgba, {
  required int width,
  required int left,
  required int top,
  required int right,
  required int bottom,
}) {
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final alpha = rgba[((y * width) + x) * 4 + 3];
      if (alpha > 12) return true;
    }
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('realtime HUD raster changes with relative recording orientation',
      () async {
    final portrait = await VideoWatermarkProcessor.generateRealtimeOverlayPng(
      snapshot: _snapshot(DeviceOrientation.portraitUp),
      width: 320,
      height: 480,
      viewportAspectRatio: 2 / 3,
    );
    final landscapeLeft =
        await VideoWatermarkProcessor.generateRealtimeOverlayPng(
      snapshot: _snapshot(DeviceOrientation.landscapeLeft),
      width: 320,
      height: 480,
      viewportAspectRatio: 3 / 2,
    );
    final landscapeRight =
        await VideoWatermarkProcessor.generateRealtimeOverlayPng(
      snapshot: _snapshot(DeviceOrientation.landscapeRight),
      width: 320,
      height: 480,
      viewportAspectRatio: 3 / 2,
    );

    expect(portrait, isNotNull);
    expect(landscapeLeft, isNotNull);
    expect(landscapeRight, isNotNull);

    // Regression guard for the Phase 7.2.1/7.2.2 overlay-lock bug: a physical
    // turn must author a different fixed-canvas HUD instead of leaving the
    // recording-start PNG permanently in place.
    expect(landscapeLeft, isNot(orderedEquals(portrait!)));
    expect(landscapeRight, isNot(orderedEquals(portrait)));
    expect(landscapeRight, isNot(orderedEquals(landscapeLeft!)));
  });

  test('SurveyCam branding follows card horizontal side at top', () async {
    final leftPng = await VideoWatermarkProcessor.generateRealtimeOverlayPng(
      snapshot: _snapshot(
        DeviceOrientation.portraitUp,
        position: WatermarkPosition.bottomLeft,
      ),
      width: 320,
      height: 480,
    );
    final rightPng = await VideoWatermarkProcessor.generateRealtimeOverlayPng(
      snapshot: _snapshot(
        DeviceOrientation.portraitUp,
        position: WatermarkPosition.bottomRight,
      ),
      width: 320,
      height: 480,
    );

    final left = await _rawRgba(leftPng!);
    final right = await _rawRgba(rightPng!);

    // Branding contains anti-aliased glyphs + a blur shadow, so testing that
    // an entire opposite half is perfectly transparent is intentionally
    // avoided. What matters is the anchor: visible mass must be on the same
    // horizontal side as the information card, while the far opposite edge
    // remains empty.
    final leftCentroid = _visiblePixelCentroidX(
      left,
      width: 320,
      top: 0,
      bottom: 90,
    );
    final rightCentroid = _visiblePixelCentroidX(
      right,
      width: 320,
      top: 0,
      bottom: 90,
    );

    expect(leftCentroid, isNotNull);
    expect(rightCentroid, isNotNull);
    expect(leftCentroid!, lessThan(160));
    expect(rightCentroid!, greaterThan(160));

    expect(
      _hasVisiblePixel(
        left,
        width: 320,
        left: 0,
        top: 0,
        right: 40,
        bottom: 90,
      ),
      isTrue,
    );
    expect(
      _hasVisiblePixel(
        left,
        width: 320,
        left: 300,
        top: 0,
        right: 320,
        bottom: 90,
      ),
      isFalse,
    );

    expect(
      _hasVisiblePixel(
        right,
        width: 320,
        left: 260,
        top: 0,
        right: 320,
        bottom: 90,
      ),
      isTrue,
    );
    expect(
      _hasVisiblePixel(
        right,
        width: 320,
        left: 0,
        top: 0,
        right: 20,
        bottom: 90,
      ),
      isFalse,
    );
  });
}
