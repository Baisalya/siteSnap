import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<void> requestCameraAndLocation() async {
    final cameraStatus = await Permission.camera.request();
    final locationStatus = await Permission.locationWhenInUse.request();

    if (!cameraStatus.isGranted || !locationStatus.isGranted) {
      throw Exception('Required permissions not granted');
    }
  }

  static Future<void> requestGalleryPermission() async {
    final status = await Permission.photos.request();
    if (!status.isGranted) {
      throw Exception('Gallery permission not granted');
    }
  }
}
