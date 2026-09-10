import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recording GPU preserves CameraX camera transform without app crop', () {
    final source = File(
      'android/camerax_patch/SiteSnapDynamicVideoSurfaceProcessor.java',
    ).readAsStringSync();

    // Camera pixels must remain under CameraX's own SurfaceOutput transform.
    // A running Recorder has a fixed encoded canvas; adding an app quarter-turn
    // here would necessarily crop, stretch, or letterbox the camera image.
    expect(
      source,
      contains(
        'target.output.updateTransformMatrix(cameraXMatrix, surfaceTextureMatrix)',
      ),
    );
    expect(
      source,
      contains(
        'vCameraCoord = (uCameraTexMatrix * vec4(aTextureCoord, 0.0, 1.0)).xy',
      ),
    );
    expect(source, isNot(contains('uDynamicMatrix')));
    expect(source, isNot(contains('buildDynamicTextureMatrix')));
    expect(source, isNot(contains('fitScale')));
    expect(source, isNot(contains('coverScale')));

    // The app-owned HUD is already rendered in final encoder coordinates.
    // Native GL only alpha-blends it; it must not reuse a camera transform.
    expect(source, contains('varying vec2 vOutputCoord'));
    expect(
      source,
      contains('vec2 overlayUv = vec2(vOutputCoord.x, 1.0 - vOutputCoord.y)'),
    );
    final controllerSource = File(
      'android/camerax_patch/SiteSnapRealtimeOverlayController.java',
    ).readAsStringSync();
    expect(
      controllerSource,
      contains('map.put("cameraTransformMode", "cameraxBasePassThrough")'),
    );
    expect(
      controllerSource,
      contains('map.put("dynamicScaleMode", "none")'),
    );
  });
}
