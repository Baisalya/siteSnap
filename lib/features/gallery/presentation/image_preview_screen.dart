import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gallery_saver/gallery_saver.dart';

import '../../../core/permissions/permission_service.dart';

class ImagePreviewScreen extends StatelessWidget {
  final File file;

  const ImagePreviewScreen({
    super.key,
    required this.file,
  });

  Future<void> _saveImage(BuildContext context) async {
    try {
      await PermissionService.requestGalleryPermission();

      // ✅ Save PROCESSED file
      await GallerySaver.saveImage(file.path);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image saved with watermark')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission denied')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Image.file(
              file,
              fit: BoxFit.contain,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Discard'),
                ),
                ElevatedButton(
                  onPressed: () => _saveImage(context),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
