import 'package:flutter/services.dart';

/// Converts SurveyCam's legacy UI/photo orientation labels into the CameraX
/// recording contract without changing the global photo/preview semantics.
///
/// The photo pipeline intentionally keeps its established orientation mapping.
/// VideoCapture historically needed the two landscape labels swapped when the
/// Activity is portrait-locked and a physical landscape target rotation is
/// applied to CameraX. Keeping this adapter recording-only prevents video
/// fixes from regressing photo preview/capture again.
DeviceOrientation toVideoCaptureOrientation(DeviceOrientation uiOrientation) {
  switch (uiOrientation) {
    case DeviceOrientation.landscapeLeft:
      return DeviceOrientation.landscapeRight;
    case DeviceOrientation.landscapeRight:
      return DeviceOrientation.landscapeLeft;
    case DeviceOrientation.portraitUp:
    case DeviceOrientation.portraitDown:
      return uiOrientation;
  }
}

/// Quarter-turn angle used to express recording-relative HUD orientation.
int videoCaptureOrientationDegrees(DeviceOrientation orientation) {
  switch (orientation) {
    case DeviceOrientation.portraitUp:
      return 0;
    case DeviceOrientation.landscapeLeft:
      return 90;
    case DeviceOrientation.portraitDown:
      return 180;
    case DeviceOrientation.landscapeRight:
      return 270;
  }
}

/// Clockwise physical-orientation delta from recording start to the current
/// phone orientation, normalized to 0/90/180/270. Camera pixels are not
/// transformed with this value; it is used only for app-owned HUD layout.
int dynamicVideoRotationDeltaDegrees(
  DeviceOrientation baseline,
  DeviceOrientation current,
) {
  final delta = videoCaptureOrientationDegrees(current) -
      videoCaptureOrientationDegrees(baseline);
  return (delta % 360 + 360) % 360;
}

/// Maps the phone's current physical orientation into the coordinate space of
/// the fixed encoder canvas chosen when recording started.
///
/// Unlike [toVideoCaptureOrientation], this uses the UI/photo orientation
/// labels directly. It is for app-owned overlay layout only; CameraX target
/// rotation and the camera pixels are deliberately not changed mid-recording.
DeviceOrientation relativeRecordingOverlayOrientation(
  DeviceOrientation recordingStartPhysicalOrientation,
  DeviceOrientation currentPhysicalOrientation,
) {
  final delta = dynamicVideoRotationDeltaDegrees(
    recordingStartPhysicalOrientation,
    currentPhysicalOrientation,
  );
  switch (delta) {
    case 90:
      return DeviceOrientation.landscapeLeft;
    case 180:
      return DeviceOrientation.portraitDown;
    case 270:
      return DeviceOrientation.landscapeRight;
    default:
      return DeviceOrientation.portraitUp;
  }
}

/// Applies the front-camera VIDEO-only HUD correction observed on Android
/// when the phone is physically in either landscape orientation. CameraX
/// already presents the front-camera pixels with its own SurfaceOutput
/// transform, but the app-owned transparent HUD is composited in output
/// coordinates. On this path the two coordinate spaces differ by 180 degrees.
///
/// Keep the correction keyed to the *current physical orientation*, not the
/// recording-start orientation. That preserves the already-correct portrait
/// VIDEO path and also fixes portrait -> landscape transitions inside one
/// recording. PHOTO/preview never call this helper.
DeviceOrientation frontCameraLandscapeVideoOverlayOrientation({
  required DeviceOrientation relativeOrientation,
  required DeviceOrientation physicalOrientation,
  required bool isFrontCamera,
}) {
  final isPhysicalLandscape =
      physicalOrientation == DeviceOrientation.landscapeLeft ||
          physicalOrientation == DeviceOrientation.landscapeRight;
  if (!isFrontCamera || !isPhysicalLandscape) return relativeOrientation;

  switch (relativeOrientation) {
    case DeviceOrientation.portraitUp:
      return DeviceOrientation.portraitDown;
    case DeviceOrientation.landscapeLeft:
      return DeviceOrientation.landscapeRight;
    case DeviceOrientation.portraitDown:
      return DeviceOrientation.portraitUp;
    case DeviceOrientation.landscapeRight:
      return DeviceOrientation.landscapeLeft;
  }
}
