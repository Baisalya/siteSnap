import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/camera/data/camera_repository_impl.dart';
import '../../features/camera/data/camera_repository_video_recording_backend.dart';
import '../../features/camera/domain/video_recording_backend.dart';
import '../../features/location/data/location_repository_impl.dart';

final cameraRepositoryProvider = Provider<CameraRepositoryImpl>((ref) {
  return CameraRepositoryImpl();
});

final videoRecordingBackendProvider = Provider<VideoRecordingBackend>((ref) {
  return CameraRepositoryVideoRecordingBackend(
    ref.read(cameraRepositoryProvider),
  );
});

final locationRepositoryProvider = Provider<LocationRepositoryImpl>((ref) {
  return LocationRepositoryImpl();
});
