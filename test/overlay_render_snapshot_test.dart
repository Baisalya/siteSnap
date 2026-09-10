import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/features/overlay/domain/WatermarkPosition.dart';
import 'package:surveycam/features/overlay/domain/overlay_model.dart';
import 'package:surveycam/features/overlay/domain/overlay_render_snapshot.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';
import 'package:surveycam/features/overlay/domain/video_overlay_sample.dart';
import 'package:surveycam/features/overlay/presentation/overlay_layout_engine.dart';

const _data = OverlayData(
  dateTime: '2026-09-09 18:30:00',
  latitude: 20.1,
  longitude: 85.2,
  altitude: 30,
  heading: 45,
  direction: 'NE',
  note: 'Site A\nColumn 4',
  position: WatermarkPosition.bottomRight,
);

const _settings = OverlaySettings(
  backgroundColor: Colors.black,
  textColor: Colors.white,
  backgroundOpacity: 0.7,
  showWeather: true,
);

void main() {
  test('render snapshot equality is value based', () {
    const first = OverlayRenderSnapshot(
      data: _data,
      settings: _settings,
      orientation: DeviceOrientation.landscapeLeft,
    );
    final second = OverlayRenderSnapshot.fromJson(first.toJson());

    expect(second, first);
    expect(second.hashCode, first.hashCode);
  });

  test('video sample carries the same render snapshot contract', () {
    const snapshot = OverlayRenderSnapshot(
      data: _data,
      settings: _settings,
      orientation: DeviceOrientation.portraitDown,
    );
    final sample = VideoOverlaySample.fromSnapshot(
      snapshot,
      timestampMs: 750,
    );

    expect(sample.snapshot, snapshot);
    expect(sample.timestampMs, 750);
  });

  test('encoded frame orientation normalization is shared geometry', () {
    expect(
      OverlayFrameGeometry.orientationForEncodedFrame(
        frameSize: const Size(1920, 1080),
        orientation: DeviceOrientation.landscapeLeft,
      ),
      DeviceOrientation.portraitUp,
    );
    expect(
      OverlayFrameGeometry.orientationForEncodedFrame(
        frameSize: const Size(1080, 1920),
        orientation: DeviceOrientation.landscapeLeft,
      ),
      DeviceOrientation.landscapeLeft,
    );
    expect(
      OverlayFrameGeometry.logicalSizeForOrientation(
        const Size(1080, 1920),
        DeviceOrientation.landscapeRight,
      ),
      const Size(1920, 1080),
    );
  });
}
