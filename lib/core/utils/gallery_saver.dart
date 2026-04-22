import 'dart:io';
import 'dart:typed_data';
import 'package:gal/gal.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class GallerySaver {
  static const String _photoCountKey = 'surveycam_photo_count';
  static SharedPreferences? _prefs;
  static bool? _hasAccessCached;

  /// Optimized save using bytes directly to avoid extra I/O
  static Future<void> saveImageBytes(Uint8List bytes) async {
    try {
      if (_hasAccessCached != true) {
        _hasAccessCached = await Gal.hasAccess();
        if (_hasAccessCached != true) {
          _hasAccessCached = await Gal.requestAccess();
        }
      }

      _prefs ??= await SharedPreferences.getInstance();
      int count = _prefs!.getInt(_photoCountKey) ?? 0;
      count++;
      _prefs!.setInt(_photoCountKey, count);

      final now = DateTime.now();
      final name = 'Surveycam_${DateFormat('yyyyMMdd_HHmmss').format(now)}_$count';

      await Gal.putImageBytes(bytes, name: name, album: 'surveycam');
    } catch (e) {
      throw Exception("Failed to save image bytes: $e");
    }
  }

  /// Saves an image file to the system gallery (optimized with rename)
  static Future<File> saveImage(File file) async {
    try {
      if (_hasAccessCached != true) {
        _hasAccessCached = await Gal.hasAccess();
        if (_hasAccessCached != true) {
          _hasAccessCached = await Gal.requestAccess();
        }
      }

      _prefs ??= await SharedPreferences.getInstance();
      int count = _prefs!.getInt(_photoCountKey) ?? 0;
      count++;
      _prefs!.setInt(_photoCountKey, count);

      final now = DateTime.now();
      final newName = 'Surveycam_${DateFormat('yyyyMMdd_HHmmss').format(now)}_$count.jpg';

      // Use rename instead of copy for speed
      final newPath = p.join(p.dirname(file.path), newName);
      File fileToSave;
      try {
        fileToSave = await file.rename(newPath);
      } catch (_) {
        fileToSave = await file.copy(newPath);
      }

      await Gal.putImage(fileToSave.path, album: 'surveycam');
      return fileToSave;
    } catch (e) {
      throw Exception("Failed to save image to gallery: $e");
    }
  }
}
