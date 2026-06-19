import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  /// CAMERA + MICROPHONE (minimum needed to open camera/video quickly)
  static Future<void> requestCameraAndMicrophone() async {
    final cameraStatus = await Permission.camera.status;
    final micStatus = await Permission.microphone.status;

    if (!cameraStatus.isGranted || !micStatus.isGranted) {
      final statuses = await [
        Permission.camera,
        Permission.microphone,
      ].request();

      final newCameraStatus = statuses[Permission.camera]!;
      final newMicStatus = statuses[Permission.microphone]!;

      if (newCameraStatus.isPermanentlyDenied ||
          newMicStatus.isPermanentlyDenied) {
        await openAppSettings();
        throw Exception('Camera or microphone permission permanently denied');
      }

      if (!newCameraStatus.isGranted || !newMicStatus.isGranted) {
        throw Exception('Camera or microphone permission not granted');
      }
    }
  }

  /// Location improves the watermark but should not block camera startup.
  static Future<void> requestLocationIfNeeded() async {
    final locationStatus = await Permission.locationWhenInUse.status;
    if (locationStatus.isGranted || locationStatus.isPermanentlyDenied) return;

    await Permission.locationWhenInUse.request();
  }

  /// CAMERA + LOCATION + MICROPHONE (used on camera start)
  static Future<void> requestCameraAndLocation() async {
    final cameraStatus = await Permission.camera.status;
    final locationStatus = await Permission.locationWhenInUse.status;
    final micStatus = await Permission.microphone.status;

    if (!cameraStatus.isGranted ||
        !locationStatus.isGranted ||
        !micStatus.isGranted) {
      final statuses = await [
        Permission.camera,
        Permission.locationWhenInUse,
        Permission.microphone,
      ].request();

      final newCameraStatus = statuses[Permission.camera]!;
      final newLocationStatus = statuses[Permission.locationWhenInUse]!;
      final newMicStatus = statuses[Permission.microphone]!;

      if (newCameraStatus.isPermanentlyDenied ||
          newLocationStatus.isPermanentlyDenied ||
          newMicStatus.isPermanentlyDenied) {
        await openAppSettings();
        throw Exception('Permissions permanently denied');
      }

      if (!newCameraStatus.isGranted ||
          !newLocationStatus.isGranted ||
          !newMicStatus.isGranted) {
        throw Exception('Required permissions not granted');
      }
    }
  }

  /// GALLERY / STORAGE (used when saving image/video)
  static Future<void> requestGalleryPermission() async {
    final granted = await requestGalleryAccessIfNeeded(
      openSettingsOnPermanentDenied: true,
    );

    if (!granted) {
      throw Exception('Gallery permission not granted');
    }
  }

  static Future<bool> requestGalleryAccessIfNeeded({
    bool openSettingsOnPermanentDenied = false,
  }) async {
    PermissionStatus status;

    if (Platform.isAndroid) {
      // Android 13+ requires specific permissions for photos and videos
      final statuses = await [
        Permission.photos,
        Permission.videos,
      ].request();

      status = statuses[Permission.photos]!.isGranted ||
              statuses[Permission.videos]!.isGranted
          ? PermissionStatus.granted
          : PermissionStatus.denied;

      // fallback for older Android
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
    } else {
      // iOS
      status = await Permission.photos.request();
    }

    if (status.isPermanentlyDenied) {
      if (openSettingsOnPermanentDenied) {
        await openAppSettings();
      }
      return false;
    }

    return status.isGranted || status.isLimited;
  }

  /// NOTIFICATION (used for background video processing)
  static Future<void> requestNotificationPermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    }
  }
}
