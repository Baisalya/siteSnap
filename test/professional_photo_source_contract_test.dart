import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CameraX still-capture patch keeps professional photo contract', () {
    final source = File('android/camerax_patch/ImageCaptureProxyApi.java')
        .readAsStringSync();
    final gradle = File('android/build.gradle').readAsStringSync();
    final provider = File(
      'android/camerax_patch/ProcessCameraProviderProxyApi.java',
    ).readAsStringSync();

    expect(
      gradle,
      contains(
        "exclude 'io/flutter/plugins/camerax/ImageCaptureProxyApi.java'",
      ),
    );
    expect(source, contains('CAPTURE_MODE_MINIMIZE_LATENCY'));
    expect(source, contains('setJpegQuality(97)'));
    expect(
      source,
      contains('builder.setResolutionSelector(resolutionSelector)'),
    );
    expect(source, isNot(contains('HIGHEST_AVAILABLE_STRATEGY')));
    expect(source, isNot(contains('RATIO_4_3_FALLBACK_AUTO_STRATEGY')));
    expect(source, contains('PHOTO_EXECUTOR'));
    expect(source, isNot(contains('Executors.newSingleThreadExecutor()')));

    expect(provider, contains('withoutIdleImageAnalysis'));
    expect(
      provider,
      contains('Thermal guard: idle ImageAnalysis left unbound'),
    );
  });
}
