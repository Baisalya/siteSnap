import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ImageUtils {
  static Future<File> createImageFile(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name.jpg');
  }
}
