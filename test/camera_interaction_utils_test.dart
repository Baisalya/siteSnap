import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/features/camera/domain/camera_interaction_utils.dart';

void main() {
  group('zoomForGesture', () {
    test('uses the zoom captured at gesture start', () {
      expect(
        zoomForGesture(
          startZoom: 2,
          scale: 1.5,
          minZoom: 1,
          maxZoom: 8,
        ),
        3,
      );
    });

    test('clamps to camera zoom capabilities', () {
      expect(
        zoomForGesture(
          startZoom: 1,
          scale: 0.1,
          minZoom: 1,
          maxZoom: 8,
        ),
        1,
      );
      expect(
        zoomForGesture(
          startZoom: 4,
          scale: 3,
          minZoom: 1,
          maxZoom: 8,
        ),
        8,
      );
    });
  });

  group('zoomForScaleDelta', () {
    test('applies only the incremental scale change', () {
      expect(
        zoomForScaleDelta(
          currentZoom: 2,
          previousScale: 1.2,
          currentScale: 1.5,
          minZoom: 1,
          maxZoom: 8,
        ),
        closeTo(2.5, 0.000001),
      );
    });

    test('reversing scale direction reverses zoom without a base jump', () {
      final zoomedIn = zoomForScaleDelta(
        currentZoom: 2,
        previousScale: 1.0,
        currentScale: 1.25,
        minZoom: 1,
        maxZoom: 8,
      );
      final zoomedBack = zoomForScaleDelta(
        currentZoom: zoomedIn,
        previousScale: 1.25,
        currentScale: 1.0,
        minZoom: 1,
        maxZoom: 8,
      );
      expect(zoomedBack, closeTo(2, 0.000001));
    });

    test('guards invalid recognizer scales and camera limits', () {
      expect(
        zoomForScaleDelta(
          currentZoom: 3,
          previousScale: 0,
          currentScale: 2,
          minZoom: 1,
          maxZoom: 8,
        ),
        3,
      );
      expect(
        zoomForScaleDelta(
          currentZoom: 7,
          previousScale: 1,
          currentScale: 2,
          minZoom: 1,
          maxZoom: 8,
        ),
        8,
      );
    });
  });

  group('formatRecordingDuration', () {
    test('formats short recordings as minutes and seconds', () {
      expect(formatRecordingDuration(const Duration(seconds: 7)), '00:07');
      expect(formatRecordingDuration(const Duration(seconds: 67)), '01:07');
    });

    test('includes hours for long field recordings', () {
      expect(
        formatRecordingDuration(const Duration(hours: 2, seconds: 5)),
        '02:00:05',
      );
    });
  });
}
