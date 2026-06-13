import 'package:camera/camera.dart';

/// Explicit quality profile for production camera behavior.
///
/// Avoid defaulting every device to ultraHigh. Budget phones can lag, heat,
/// or crash when high-resolution capture and overlay processing happen at
/// the same time.
enum CameraQualityProfile {
  balanced,
  high,
  proofMax,
}

extension CameraQualityProfileX on CameraQualityProfile {
  ResolutionPreset get resolutionPreset {
    switch (this) {
      case CameraQualityProfile.balanced:
        return ResolutionPreset.high;
      case CameraQualityProfile.high:
        return ResolutionPreset.veryHigh;
      case CameraQualityProfile.proofMax:
        return ResolutionPreset.ultraHigh;
    }
  }

  String get label {
    switch (this) {
      case CameraQualityProfile.balanced:
        return 'Balanced';
      case CameraQualityProfile.high:
        return 'High';
      case CameraQualityProfile.proofMax:
        return 'Proof Max';
    }
  }
}
