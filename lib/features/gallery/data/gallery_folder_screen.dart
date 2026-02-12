import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

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

  /// ✅ Selection mode
  Set<File> selectedImages = {};
  bool selectionMode = false;

  final repo = SiteSnapGalleryRepository();

  @override
  void initState() {
    super.initState();
    _initGallery();
  }

  /// ===============================
  /// INIT
  /// ===============================
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

  /// ===============================
  /// SHARE SELECTED
  /// ===============================
  void _shareSelected() {
    if (selectedImages.isEmpty) return;

    Share.shareXFiles(
      selectedImages.map((f) => XFile(f.path)).toList(),
    );
  }

  /// ===============================
  /// BUILD
  /// ===============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          selectionMode
              ? "${selectedImages.length} selected"
              : "SiteSnap Photos",

        ),
        actions: [
          if (selectionMode)
            IconButton(
              icon: const Icon(Icons.share),
              color: Colors.white,
              onPressed: _shareSelected,
            ),
        ],
        leading: selectionMode
            ? IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            setState(() {
              selectionMode = false;
              selectedImages.clear();
            });
          },
        )
            : null,
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
            /// ✅ LONG PRESS → ENTER SELECTION MODE
            onLongPress: () {
              setState(() {
                selectionMode = true;
                selectedImages.add(file);
              });
            },
            /// ✅ TAP
            onTap: () {
              if (selectionMode) {
                setState(() {
                  if (selectedImages.contains(file)) {
                    selectedImages.remove(file);
                  } else {
                    selectedImages.add(file);
                  }

                  if (selectedImages.isEmpty) {
                    selectionMode = false;
                  }
                });
              } else {
                /// Open swipe viewer
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GalleryImageViewer(
                      images: images,
                      initialIndex: i,
                    ),
                  ),
                );
              }
            },

            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.file(
                    file,
                    fit: BoxFit.cover,
                  ),
                ),

                /// ✅ Selected indicator
                if (selectedImages.contains(file))
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue,
                      ),
                      padding: const EdgeInsets.all(4),
                      child: const Icon(
                        Icons.check,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
