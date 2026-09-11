import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _compactDartSource(String source) =>
    source.replaceAll(RegExp(r'\s+'), '');

void main() {
  test('pinch zoom is frame-synchronised, superseding, and gesture-aware', () {
    final viewModelSource = File(
      'lib/features/camera/presentation/camera_viewmodel.dart',
    ).readAsStringSync();
    final screenSource = File(
      'lib/features/camera/presentation/camera_screen.dart',
    ).readAsStringSync();
    final hudSource = File(
      'lib/features/camera/presentation/camera_zoom_hud.dart',
    ).readAsStringSync();
    final compactScreenSource = _compactDartSource(screenSource);

    final zoomStart = viewModelSource.indexOf('// ================= ZOOM');
    final zoomEnd = viewModelSource.indexOf('/// Soft flash quench only.');
    expect(zoomStart, greaterThanOrEqualTo(0));
    expect(zoomEnd, greaterThan(zoomStart));
    final zoomSection = viewModelSource.substring(zoomStart, zoomEnd);

    expect(zoomSection, contains('beginZoomGesture()'));
    expect(zoomSection, contains('updateZoomGesture(double zoom)'));
    expect(zoomSection, contains('endZoomGesture(double zoom)'));
    expect(zoomSection, contains('_pendingZoom'));
    expect(zoomSection, contains('scheduleFrameCallback'));
    expect(zoomSection, contains('cancelFrameCallbackWithId'));
    expect(zoomSection, contains('_submitGestureZoom'));
    expect(zoomSection, isNot(contains('runExclusive')));
    expect(zoomSection, isNot(contains('Duration(milliseconds: 16)')));
    expect(zoomSection, isNot(contains('Duration(milliseconds: 80)')));

    final submitStart = zoomSection.indexOf('void _submitGestureZoom(');
    final supersedingStart =
        zoomSection.indexOf('Future<void> _applySupersedingZoom');
    final finalCommitStart =
        zoomSection.indexOf('Future<void> _commitFinalZoom');
    expect(submitStart, greaterThanOrEqualTo(0));
    expect(supersedingStart, greaterThan(submitStart));
    expect(finalCommitStart, greaterThan(supersedingStart));
    final directGestureSubmit =
        zoomSection.substring(submitStart, supersedingStart);
    expect(directGestureSubmit, contains('unawaited(_applySupersedingZoom'));
    expect(directGestureSubmit, isNot(contains('runExclusive')));

    expect(screenSource, contains('ValueNotifier<double> _zoomHudValue'));
    expect(screenSource, contains('zoomForScaleDelta('));
    expect(screenSource, contains('_zoomPointerCount'));
    expect(screenSource, contains('CameraZoomHud('));
    expect(
      compactScreenSource,
      contains('cameraVM.updateZoomGesture(targetZoom)'),
    );
    expect(
      compactScreenSource,
      contains('cameraVM.endZoomGesture(finalZoom)'),
    );
    expect(
      compactScreenSource,
      isNot(contains('cameraVM.setZoom(zoomForGesture(')),
    );

    // The live numeric/ruler values must not tween behind the fingers. Only
    // show/hide/container affordances may animate.
    expect(hudSource, isNot(contains('AnimatedSwitcher(')));
    expect(hudSource, contains('if (isGestureActive)'));
    expect(hudSource, contains('Align('));
  });
}
