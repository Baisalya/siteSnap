import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/features/camera/domain/video_capture_orientation.dart';

void main() {
  test('recording orientation adapter isolates CameraX landscape semantics',
      () {
    expect(
      toVideoCaptureOrientation(DeviceOrientation.landscapeLeft),
      DeviceOrientation.landscapeRight,
    );
    expect(
      toVideoCaptureOrientation(DeviceOrientation.landscapeRight),
      DeviceOrientation.landscapeLeft,
    );
    expect(
      toVideoCaptureOrientation(DeviceOrientation.portraitUp),
      DeviceOrientation.portraitUp,
    );
    expect(
      toVideoCaptureOrientation(DeviceOrientation.portraitDown),
      DeviceOrientation.portraitDown,
    );
  });

  test('relative HUD orientation is measured from recording start', () {
    expect(
      relativeRecordingOverlayOrientation(
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitUp,
      ),
      DeviceOrientation.portraitUp,
    );
    expect(
      relativeRecordingOverlayOrientation(
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
      ),
      DeviceOrientation.landscapeLeft,
    );
    expect(
      relativeRecordingOverlayOrientation(
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeRight,
      ),
      DeviceOrientation.landscapeRight,
    );
    expect(
      relativeRecordingOverlayOrientation(
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.portraitUp,
      ),
      DeviceOrientation.landscapeRight,
    );
    expect(
      relativeRecordingOverlayOrientation(
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ),
      DeviceOrientation.landscapeLeft,
    );
    expect(
      relativeRecordingOverlayOrientation(
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ),
      DeviceOrientation.portraitDown,
    );
  });

  test('front camera video half-turn is landscape-current only', () {
    // Portrait-start -> landscape-left.
    expect(
      frontCameraLandscapeVideoOverlayOrientation(
        relativeOrientation: DeviceOrientation.landscapeLeft,
        physicalOrientation: DeviceOrientation.landscapeLeft,
        isFrontCamera: true,
      ),
      DeviceOrientation.landscapeRight,
    );

    // Portrait-start -> landscape-right.
    expect(
      frontCameraLandscapeVideoOverlayOrientation(
        relativeOrientation: DeviceOrientation.landscapeRight,
        physicalOrientation: DeviceOrientation.landscapeRight,
        isFrontCamera: true,
      ),
      DeviceOrientation.landscapeLeft,
    );

    // Recording that starts in landscape also needs the same half-turn.
    expect(
      frontCameraLandscapeVideoOverlayOrientation(
        relativeOrientation: DeviceOrientation.portraitUp,
        physicalOrientation: DeviceOrientation.landscapeLeft,
        isFrontCamera: true,
      ),
      DeviceOrientation.portraitDown,
    );

    // Front portrait VIDEO is already correct.
    expect(
      frontCameraLandscapeVideoOverlayOrientation(
        relativeOrientation: DeviceOrientation.portraitUp,
        physicalOrientation: DeviceOrientation.portraitUp,
        isFrontCamera: true,
      ),
      DeviceOrientation.portraitUp,
    );

    // Back-camera VIDEO is already correct in landscape.
    expect(
      frontCameraLandscapeVideoOverlayOrientation(
        relativeOrientation: DeviceOrientation.landscapeLeft,
        physicalOrientation: DeviceOrientation.landscapeLeft,
        isFrontCamera: false,
      ),
      DeviceOrientation.landscapeLeft,
    );
  });

  test('relative HUD delta is normalized to quarter turns', () {
    expect(
      dynamicVideoRotationDeltaDegrees(
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
      ),
      90,
    );
    expect(
      dynamicVideoRotationDeltaDegrees(
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeRight,
      ),
      270,
    );
    expect(
      dynamicVideoRotationDeltaDegrees(
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.portraitUp,
      ),
      270,
    );
  });
}
