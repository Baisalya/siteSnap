import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:survaycam/features/gallery/data/sitesnap_gallery_repository.dart';
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

  final repo = survaycamGalleryRepository();

  @override
  void initState() {
    super.initState();
    _initGallery();
  }

  /// ================= INIT =================
  Future<void> _initGallery() async {
    final granted = await _requestPermission();
    if (!granted) return;

    await _loadImages();
  }

  /// ================= PERMISSION =================
  Future<bool> _requestPermission() async {
    final status = await Permission.photos.request();

    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      openAppSettings();
    }

    return false;
  }

  /// ================= LOAD =================
  Future<void> _loadImages() async {
    final result = await repo.loadImages();

    if (!mounted) return;

    setState(() {
      images = result;
      loading = false;
    });
  }

  /// ================= SHARE =================
  void _shareSelected() {
    if (selectedImages.isEmpty) return;

    Share.shareXFiles(
      selectedImages.map((f) => XFile(f.path)).toList(),
      text: "Shared from SurveyCam 📷",
    );
  }

  /// ================= SELECT =================
  void _toggleSelection(File file) {
    setState(() {
      if (selectedImages.contains(file)) {
        selectedImages.remove(file);
      } else {
        selectedImages.add(file);
      }

      selectionMode = selectedImages.isNotEmpty;
    });
  }

  void _selectAll() {
    setState(() {
      selectedImages = images.toSet();
      selectionMode = true;
    });
  }

  void _clearSelection() {
    setState(() {
      selectedImages.clear();
      selectionMode = false;
    });
  }

  /// ================= BUILD =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      /// ================= APPBAR =================
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.black,

        leading: selectionMode
            ? IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: _clearSelection,
        )
            : null,

        title: selectionMode
            ? Text(
          "${selectedImages.length} selected",
          style: const TextStyle(color: Colors.white),
        )
            : const Text(
          "SurveyCam Photos",
          style: TextStyle(color: Colors.white),
        ),

        actions: [
          if (selectionMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all, color: Colors.white),
              onPressed: _selectAll,
            ),
            IconButton(
              icon: const Icon(Icons.share, color: Colors.white),
              onPressed: _shareSelected,
            ),
          ],
        ],
      ),

      /// ================= BODY =================
      body: loading
          ? _loadingView()
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
          final isSelected = selectedImages.contains(file);

          return _buildGridItem(file, i, isSelected);
        },
      ),
    );
  }

  /// ================= GRID ITEM =================
  Widget _buildGridItem(File file, int index, bool isSelected) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),

        onLongPress: () {
          setState(() {
            selectionMode = true;
            selectedImages.add(file);
          });
        },

        onTap: () {
          if (selectionMode) {
            _toggleSelection(file);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GalleryImageViewer(
                  images: images,
                  initialIndex: index,
                ),
              ),
            );
          }
        },

        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(color: Colors.blue, width: 2)
                : null,
          ),
          child: Stack(
            children: [

              /// 🔥 HERO IMAGE
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Hero(
                  tag: file.path,
                  child: Image.file(
                    file,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,

                    /// 🚀 PERFORMANCE BOOST
                    cacheWidth: 300,
                  ),
                ),
              ),

              /// overlay
              if (isSelected)
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.black.withOpacity(0.4),
                  ),
                ),

              /// check icon
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
      ),
    );
  }

  /// ================= LOADING =================
  Widget _loadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 12),
          Text(
            "Loading photos...",
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  /// ================= EMPTY =================
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
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
          SizedBox(height: 6),
          Text(
            "Capture photos to see them here",
            style: TextStyle(color: Colors.white38),
          ),
        ],
      ),
    );
  }
}