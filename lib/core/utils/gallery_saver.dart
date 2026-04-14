import 'dart:io';
import 'package:gal/gal.dart';

class GallerySaver {
  /// Saves an image to the system gallery under the 'survaycam' album.
  /// This replaces the manual file copying and 'image_gallery_saver' calls.
  static Future<File> saveImage(File file) async {
    try {
      // 1. Check and request permissions
      if (!await Gal.hasAccess()) {
        await Gal.requestAccess();
      }

      // 2. Save to Gallery
      // 'album' handles creating the 'survaycam' folder/album on both Android and iOS.
      // On Android, this uses MediaStore to save to the public Pictures folder.
      // On iOS, this saves to the Photos app under the specified album.
      await Gal.putImage(file.path, album: 'survaycam');

      // 3. Return the file
      // Since Gal creates its own copy in the gallery, we return the 
      // original file to maintain compatibility with your existing code.
      return file;
    } catch (e) {
      // Replicates your old error handling logic
      throw Exception("Failed to save image to gallery: $e");
    }
  }
}
