import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {

  /// CAMERA + LOCATION (used on camera start)
  static Future<void> requestCameraAndLocation() async {
    final cameraStatus = await Permission.camera.request();
    final locationStatus = await Permission.locationWhenInUse.request();

    if (cameraStatus.isPermanentlyDenied ||
        locationStatus.isPermanentlyDenied) {
      await openAppSettings();
      throw Exception('Permissions permanently denied');
    }

    if (!cameraStatus.isGranted || !locationStatus.isGranted) {
      throw Exception('Required permissions not granted');
    }
  }

  /// GALLERY / STORAGE (used when saving image)
  static Future<void> requestGalleryPermission() async {
    PermissionStatus status;

    if (Platform.isAndroid) {
      // Android 13+
      status = await Permission.photos.request();

      // fallback for older Android
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
    } else {
      // iOS
      status = await Permission.photos.request();
    }

    if (status.isPermanentlyDenied) {
      await openAppSettings();
      throw Exception('Gallery permission permanently denied');
    }

    if (!status.isGranted) {
      throw Exception('Gallery permission not granted');
    }
  }
}
