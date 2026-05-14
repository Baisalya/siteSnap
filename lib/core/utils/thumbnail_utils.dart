import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_video_thumbnail_plus/flutter_video_thumbnail_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class ThumbnailUtils {
  static Future<String?> generateVideoThumbnail(String videoPath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final fileName = p.basenameWithoutExtension(videoPath);
      final thumbnailPath = p.join(tempDir.path, 'thumb_$fileName.jpg');

      if (await File(thumbnailPath).exists()) {
        return thumbnailPath;
      }

      return await FlutterVideoThumbnailPlus.thumbnailFile(
        video: videoPath,
        thumbnailPath: tempDir.path,
        imageFormat: ImageFormat.jpeg,
        maxWidth: 300,
        quality: 75,
      );
    } catch (e) {
      debugPrint("Thumbnail generation error: $e");
      return null;
    }
  }
}
