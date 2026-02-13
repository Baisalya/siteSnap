import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

class ExifUtils {

  /// Camera plugin already saves correct EXIF orientation.
  /// Do NOT rotate pixels manually.
  ///
  /// Just return original file.
  static Future<File> fixImageOrientation({
    required File file,
    required DeviceOrientation deviceOrientation,
  }) async {
    return file;
  }
}
