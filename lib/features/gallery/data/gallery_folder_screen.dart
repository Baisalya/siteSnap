import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:surveycam/features/gallery/data/sitesnap_gallery_repository.dart';
import 'package:surveycam/features/gallery/presentation/gallery_image_viewer.dart';
import 'package:surveycam/features/gallery/presentation/video_player_screen.dart';
import 'package:flutter_video_thumbnail_plus/flutter_video_thumbnail_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:surveycam/core/utils/thumbnail_utils.dart';

class GalleryFolderScreen extends ConsumerStatefulWidget {
  const GalleryFolderScreen({super.key});

  @override
  ConsumerState<GalleryFolderScreen> createState() =>
      _GalleryFolderScreenState();
}

class _GalleryFolderScreenState extends ConsumerState<GalleryFolderScreen> {
  Set<File> selectedImages = {};
  bool selectionMode = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final status = await Permission.photos.status;
    if (status.isDenied) {
      await Permission.photos.request();
    }
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

  void _selectAll(List<File> images) {
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
    final galleryAsync = ref.watch(galleryFilesProvider);

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
                "SurveyCam Gallery",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
        actions: [
          if (selectionMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all, color: Colors.white),
              onPressed: () {
                galleryAsync.whenData((images) => _selectAll(images));
              },
            ),
            IconButton(
              icon: const Icon(Icons.share, color: Colors.white),
              onPressed: _shareSelected,
            ),
          ],
        ],
      ),

      /// ================= BODY =================
      body: galleryAsync.when(
        data: (images) {
          if (images.isEmpty) return _emptyView();

          return RefreshIndicator(
            onRefresh: () => ref.refresh(galleryFilesProvider.future),
            color: Colors.amberAccent,
            backgroundColor: Colors.grey[900],
            child: GridView.builder(
              padding: const EdgeInsets.all(6),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: images.length,
              itemBuilder: (_, i) {
                final file = images[i];
                final isSelected = selectedImages.contains(file);
                return _buildGridItem(file, i, isSelected, images);
              },
            ),
          );
        },
        loading: () => _loadingView(),
        error: (err, stack) => Center(
          child: Text("Error: $err", style: const TextStyle(color: Colors.red)),
        ),
      ),
    );
  }

  /// ================= GRID ITEM =================
  Widget _buildGridItem(File file, int index, bool isSelected, List<File> allImages) {
    final isVideo = file.path.toLowerCase().endsWith('.mp4') ||
        file.path.toLowerCase().endsWith('.mov');

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
            if (isVideo) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VideoPlayerScreen(file: file),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GalleryImageViewer(
                    images: allImages,
                    initialIndex: index,
                  ),
                ),
              );
            }
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
              /// 🔥 HERO IMAGE / THUMBNAIL
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Hero(
                  tag: file.path,
                  child: isVideo
                      ? FutureBuilder<String?>(
                          future: _generateThumbnail(file.path),
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data != null) {
                              return Image.file(
                                File(snapshot.data!),
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                cacheWidth: 300,
                              );
                            }
                            return Container(
                              color: Colors.grey[900],
                              child: const Icon(Icons.video_library,
                                  color: Colors.white24),
                            );
                          },
                        )
                      : Image.file(
                          file,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          cacheWidth: 300,
                        ),
                ),
              ),

              /// Play icon for videos
              if (isVideo)
                const Center(
                  child: Icon(
                    Icons.play_circle_outline,
                    color: Colors.white70,
                    size: 32,
                  ),
                ),

              /// overlay
              if (isSelected)
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.black.withValues(alpha: 0.4),
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

  Future<String?> _generateThumbnail(String videoPath) async {
    return await ThumbnailUtils.generateVideoThumbnail(videoPath);
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