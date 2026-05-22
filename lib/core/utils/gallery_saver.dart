import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:gal/gal.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GallerySaver {
  static const String _imageCountKey = 'surveycam_image_count';
  static const String _videoCountKey = 'surveycam_video_count';
  static SharedPreferences? _prefs;
  static bool? _hasAccessCached;

  static Future<void> warmUp() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static Future<Directory> localAlbumDirectory() async {
    final docDir = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(docDir.path, 'surveycam'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// Saves a local copy first so the in-app gallery can update immediately.
  static Future<File> saveImageBytes(Uint8List bytes) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      int count = _prefs!.getInt(_imageCountKey) ?? 0;
      count++;
      unawaited(_prefs!.setInt(_imageCountKey, count));

      final now = DateTime.now();
      final name =
          'SurveyCam_${DateFormat('yyyyMMdd_HHmmss').format(now)}_$count.jpg';
      final localDir = await localAlbumDirectory();
      final localFile = File(p.join(localDir.path, name));

      await localFile.writeAsBytes(bytes, flush: false);
      unawaited(_putImageInSystemGallery(localFile.path));

      return localFile;
    } catch (e) {
      throw Exception("Failed to save image bytes: $e");
    }
  }

  static Future<void> _putImageInSystemGallery(String path) async {
    try {
      if (_hasAccessCached != true) {
        _hasAccessCached = await Gal.hasAccess();
        if (_hasAccessCached != true) {
          _hasAccessCached = await Gal.requestAccess();
        }
      }

      await Gal.putImage(path, album: 'surveycam');
    } catch (_) {
      _hasAccessCached = false;
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
      final extension =
          p.extension(file.path).isEmpty ? '.jpg' : p.extension(file.path);
      final newName =
          'SurveyCam_${DateFormat('yyyyMMdd_HHmmss').format(now)}_$count$extension';

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

  static Future<String> saveVideo(String path) async {
    try {
      // 1. Save a local copy first in the app's documents directory
      // This ensures the in-app gallery can find it immediately
      final localDir = await localAlbumDirectory();
      final videoFile = File(path);
      final now = DateTime.now();

      _prefs ??= await SharedPreferences.getInstance();
      int count = _prefs!.getInt(_videoCountKey) ?? 0;
      count++;
      unawaited(_prefs!.setInt(_videoCountKey, count));

      final extension = p.extension(path).isEmpty ? '.mp4' : p.extension(path);
      final name =
          'SurveyCam_${DateFormat('yyyyMMdd_HHmmss').format(now)}_$count$extension';
      final localPath = p.join(localDir.path, name);

      String finalLocalPath = localPath;
      try {
        final renamedFile = await videoFile.rename(localPath);
        finalLocalPath = renamedFile.path;
      } catch (_) {
        final copiedFile = await videoFile.copy(localPath);
        finalLocalPath = copiedFile.path;
      }

      // 2. Put in system gallery asynchronously
      unawaited(_putVideoInSystemGallery(finalLocalPath));

      return finalLocalPath;
    } catch (e) {
      throw Exception("Failed to save video: $e");
    }
  }

  static Future<void> _putVideoInSystemGallery(String path) async {
    try {
      if (_hasAccessCached != true) {
        _hasAccessCached = await Gal.hasAccess();
        if (_hasAccessCached != true) {
          _hasAccessCached = await Gal.requestAccess();
        }
      }
      await Gal.putVideo(path, album: 'surveycam');
    } catch (_) {
      _hasAccessCached = false;
    }
  }
}
