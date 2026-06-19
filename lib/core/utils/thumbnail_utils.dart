import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_video_thumbnail_plus/flutter_video_thumbnail_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class ThumbnailUtils {
  static String? _tempDirPath;

  static Future<String?> generateVideoThumbnail(
    String videoPath, {
    int maxWidth = 1280,
    int quality = 90,
  }) async {
    try {
      _tempDirPath ??= (await getTemporaryDirectory()).path;
      final fileName = p.basenameWithoutExtension(videoPath);
      // Append resolution and quality to filename to avoid using low-quality cached versions
      final thumbnailPath =
          p.join(_tempDirPath!, 'thumb_${fileName}_${maxWidth}q$quality.jpg');

      if (await File(thumbnailPath).exists()) {
        return thumbnailPath;
      }

      return await FlutterVideoThumbnailPlus.thumbnailFile(
        video: videoPath,
        thumbnailPath: _tempDirPath!,
        imageFormat: ImageFormat.jpeg,
        maxWidth: maxWidth,
        quality: quality,
      );
    } catch (e) {
      debugPrint("Thumbnail generation error: $e");
      return null;
    }
  }
}
