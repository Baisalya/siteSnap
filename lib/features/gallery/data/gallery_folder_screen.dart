import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../gallery/data/sitesnap_gallery_repository.dart';
import '../presentation/gallery_image_viewer.dart';

class GalleryFolderScreen extends StatefulWidget {
  const GalleryFolderScreen({super.key});

  @override
  State<GalleryFolderScreen> createState() =>
      _GalleryFolderScreenState();
}

class _GalleryFolderScreenState extends State<GalleryFolderScreen> {
  List<File> images = [];
  bool loading = true;

  final repo = SiteSnapGalleryRepository();

  @override
  void initState() {
    super.initState();
    _initGallery();
  }

  /// ✅ Ask permission first
  Future<void> _initGallery() async {
    await _requestPermission();
    await _loadImages();
  }

  Future<void> _requestPermission() async {
    if (Platform.isAndroid) {
      await Permission.photos.request();
      await Permission.storage.request();
    } else if (Platform.isIOS) {
      await Permission.photos.request();
    }
  }

  Future<void> _loadImages() async {
    final result = await repo.loadImages();

    if (!mounted) return;

    setState(() {
      images = result;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('SiteSnap Photos'),
        backgroundColor: Colors.black,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : images.isEmpty
          ? const Center(
        child: Text(
          'No photos yet',
          style: TextStyle(color: Colors.white),
        ),
      )
          : GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate:
        const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: images.length,
        itemBuilder: (_, i) {
          final file = images[i];

          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      GalleryImageViewer(file: file),
                ),
              );
            },
            child: Image.file(
              file,
              fit: BoxFit.cover,
            ),
          );
        },
      ),
    );
  }
}
