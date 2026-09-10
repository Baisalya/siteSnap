import 'package:camera/camera.dart' hide CameraLensType;
import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/features/camera/data/camera_repository_video_recording_backend.dart';
import 'package:surveycam/features/camera/domain/camera_lens_type.dart';
import 'package:surveycam/features/camera/domain/camera_repository.dart';

class _FakeCameraRepository implements CameraRepository {
  int starts = 0;
  int stops = 0;

  @override
  CameraController? get controller => null;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize(CameraLensType lens) async {}

  @override
  Future<void> startVideoRecording() async {
    starts++;
  }

  @override
  Future<bool> switchLensWhileRecording(CameraLensType lens) async => true;

  @override
  Future<XFile> stopVideoRecording() async {
    stops++;
    return XFile('/tmp/recording.mp4');
  }

  @override
  Future<String> takePicture() async => '/tmp/photo.jpg';
}

void main() {
  test('camera repository adapter exposes stable recording backend', () async {
    final repository = _FakeCameraRepository();
    final backend = CameraRepositoryVideoRecordingBackend(repository);

    await backend.start();
    final path = await backend.stop();

    expect(repository.starts, 1);
    expect(repository.stops, 1);
    expect(path, '/tmp/recording.mp4');
  });
}
