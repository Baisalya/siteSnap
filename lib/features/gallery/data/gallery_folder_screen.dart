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

  Set<File> selectedImages = {};
  bool selectionMode = false;

  final repo = SiteSnapGalleryRepository();

  @override
  void initState() {
    super.initState();
    _initGallery();
  }

  Future<void> _initGallery() async {
    await _requestPermission();
    await _loadImages();
  }

  Future<void> _requestPermission() async {
    if (Platform.isAndroid) {
      await Permission.photos.request();
      await Permission.storage.request();
    } else {
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

  void _shareSelected() {
    if (selectedImages.isEmpty) return;

    Share.shareXFiles(
      selectedImages.map((f) => XFile(f.path)).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      // ================= APPBAR =================
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.black,
        title: selectionMode
            ? Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            "${selectedImages.length} selected",
            style: const TextStyle(fontSize: 16,color: Colors.white),
          ),
        )
            : const Text("SiteSnap Photos",style: TextStyle(color: Colors.white),),
        actions: [
          if (selectionMode)
            IconButton(
              icon: const Icon(Icons.share,color: Colors.white,),
              onPressed: _shareSelected,
            ),
        ],
        leading: selectionMode
            ? IconButton(
          icon: const Icon(Icons.close,color: Colors.white,),
          onPressed: () {
            setState(() {
              selectionMode = false;
              selectedImages.clear();
            });
          },
        )
            : null,
      ),

      // ================= BODY =================
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : images.isEmpty
          ? _emptyView()
          : GridView.builder(
        padding: const EdgeInsets.all(6),
        gridDelegate:
        const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
        ),
        itemCount: images.length,
        itemBuilder: (_, i) {
          final file = images[i];
          final isSelected =
          selectedImages.contains(file);

          return GestureDetector(
            onLongPress: () {
              setState(() {
                selectionMode = true;
                selectedImages.add(file);
              });
            },
            onTap: () {
              if (selectionMode) {
                setState(() {
                  if (isSelected) {
                    selectedImages.remove(file);
                  } else {
                    selectedImages.add(file);
                  }

                  if (selectedImages.isEmpty) {
                    selectionMode = false;
                  }
                });
              } else {
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

            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: isSelected
                    ? Border.all(
                  color: Colors.blue,
                  width: 2,
                )
                    : null,
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius:
                    BorderRadius.circular(10),
                    child: Image.file(
                      file,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),

                  /// Selection overlay
                  if (isSelected)
                    Container(
                      decoration: BoxDecoration(
                        borderRadius:
                        BorderRadius.circular(10),
                        color: Colors.black.withOpacity(0.35),
                      ),
                    ),

                  /// Check icon
                  if (isSelected)
                    const Positioned(
                      top: 6,
                      right: 6,
                      child: CircleAvatar(
                        radius: 10,
                        backgroundColor: Colors.blue,
                        child: Icon(
                          Icons.check,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// ================= EMPTY VIEW =================
  Widget _emptyView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined,
              size: 64, color: Colors.white38),
          SizedBox(height: 12),
          Text(
            "No photos yet",
            style: TextStyle(
              color: Colors.white54,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
