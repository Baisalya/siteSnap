import 'dart:io';

class ExifUtils {
  static Future<File> preserveExif({
    required File source,
    required File destination,
  }) async {
    // Image package preserves EXIF by default if you reuse original bytes
    await destination.writeAsBytes(await source.readAsBytes());
    return destination;
  }
}
