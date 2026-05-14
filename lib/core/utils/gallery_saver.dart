import 'dart:io';
import 'dart:typed_data';
import 'package:gal/gal.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class GallerySaver {
  static const String _imageCountKey = 'surveycam_image_count';
  static const String _videoCountKey = 'surveycam_video_count';
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
      int count = _prefs!.getInt(_imageCountKey) ?? 0;
      count++;
      _prefs!.setInt(_imageCountKey, count);

      final now = DateTime.now();
      final name = 'SurveyCam_${DateFormat('yyyyMMdd_HHmmss').format(now)}_$count';

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
      int count = _prefs!.getInt(_imageCountKey) ?? 0;
      count++;
      _prefs!.setInt(_imageCountKey, count);

      final now = DateTime.now();
      final extension = p.extension(file.path).isEmpty ? '.jpg' : p.extension(file.path);
      final newName = 'SurveyCam_${DateFormat('yyyyMMdd_HHmmss').format(now)}_$count$extension';

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

  static Future<void> saveVideo(String path) async {
    try {
      if (_hasAccessCached != true) {
        _hasAccessCached = await Gal.hasAccess();
        if (_hasAccessCached != true) {
          _hasAccessCached = await Gal.requestAccess();
        }
      }

      _prefs ??= await SharedPreferences.getInstance();
      int count = _prefs!.getInt(_videoCountKey) ?? 0;
      count++;
      _prefs!.setInt(_videoCountKey, count);

      final now = DateTime.now();
      final videoFile = File(path);
      final extension = p.extension(path).isEmpty ? '.mp4' : p.extension(path);
      final newName = 'SurveyCam_${DateFormat('yyyyMMdd_HHmmss').format(now)}_$count$extension';
      
      final newPath = p.join(p.dirname(path), newName);
      
      String finalPath = path;
      try {
        final renamedFile = await videoFile.rename(newPath);
        finalPath = renamedFile.path;
      } catch (_) {
        final copiedFile = await videoFile.copy(newPath);
        finalPath = copiedFile.path;
      }

      await Gal.putVideo(finalPath, album: 'surveycam');
    } catch (e) {
      throw Exception("Failed to save video to gallery: $e");
    }
  }
}
