import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:surveycam/features/gallery/data/sitesnap_gallery_repository.dart';
import 'package:surveycam/features/gallery/presentation/gallery_image_viewer.dart';
import 'package:surveycam/features/gallery/presentation/video_player_screen.dart';
import 'package:surveycam/core/utils/thumbnail_utils.dart';

final gallerySelectionProvider = StateProvider<Set<File>>((ref) => {});

class GalleryFolderScreen extends ConsumerStatefulWidget {
  const GalleryFolderScreen({super.key});

  @override
  ConsumerState<GalleryFolderScreen> createState() =>
      _GalleryFolderScreenState();
}

class _GalleryFolderScreenState extends ConsumerState<GalleryFolderScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(
      () => ref.read(galleryFilesProvider.notifier).ensureLoaded(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(galleryFilesProvider.notifier).ensureLoaded();
    }
  }

  /// ================= SHARE =================
  void _shareSelected() {
    final selectedImages = ref.read(gallerySelectionProvider);
    if (selectedImages.isEmpty) return;

    Share.shareXFiles(
      selectedImages.map((f) => XFile(f.path)).toList(),
      text: "Shared from SurveyCam 📷",
    );
  }

  /// ================= SELECT =================
  void _selectAll(List<File> images) {
    ref.read(gallerySelectionProvider.notifier).state = images.toSet();
  }

  void _clearSelection() {
    ref.read(gallerySelectionProvider.notifier).state = {};
  }

  /// ================= BUILD =================
  @override
  Widget build(BuildContext context) {
    final galleryAsync = ref.watch(galleryFilesProvider);
    final selectedImages = ref.watch(gallerySelectionProvider);
    final selectionMode = selectedImages.isNotEmpty;

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
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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

          return _galleryGrid(images);
        },
        loading: () {
          final cachedImages =
              ref.read(galleryRepositoryProvider).cachedFiles ?? const <File>[];
          return cachedImages.isEmpty
              ? _loadingView()
              : _galleryGrid(cachedImages);
        },
        error: (err, stack) => Center(
          child: Text("Error: $err", style: const TextStyle(color: Colors.red)),
        ),
      ),
    );
  }

  Widget _galleryGrid(List<File> images) {
    return RefreshIndicator(
      onRefresh: () => ref.read(galleryFilesProvider.notifier).refresh(),
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
        itemBuilder: (context, i) {
          final file = images[i];
          return GalleryItem(
            key: ValueKey(file.path),
            file: file,
            index: i,
            allImages: images,
          );
        },
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
          Icon(Icons.photo_library_outlined, size: 64, color: Colors.white38),
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

class GalleryItem extends ConsumerWidget {
  final File file;
  final int index;
  final List<File> allImages;

  const GalleryItem({
    super.key,
    required this.file,
    required this.index,
    required this.allImages,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedImages = ref.watch(gallerySelectionProvider);
    final isSelected = selectedImages.contains(file);
    final selectionMode = selectedImages.isNotEmpty;

    final isVideo = file.path.toLowerCase().endsWith('.mp4') ||
        file.path.toLowerCase().endsWith('.mov');

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onLongPress: () {
            ref
                .read(gallerySelectionProvider.notifier)
                .update((state) => {...state, file});
          },
          onTap: () {
            if (selectionMode) {
              ref.read(gallerySelectionProvider.notifier).update((state) {
                final newState = {...state};
                if (newState.contains(file)) {
                  newState.remove(file);
                } else {
                  newState.add(file);
                }
                return newState;
              });
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
              border:
                  isSelected ? Border.all(color: Colors.blue, width: 2) : null,
            ),
            child: Stack(
              children: [
                /// 🔥 HERO IMAGE / THUMBNAIL
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Hero(
                    tag: file.path,
                    child: isVideo
                        ? VideoThumbnailWidget(videoPath: file.path)
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
      ),
    );
  }
}

class VideoThumbnailWidget extends StatefulWidget {
  final String videoPath;
  const VideoThumbnailWidget({super.key, required this.videoPath});

  @override
  State<VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<VideoThumbnailWidget> {
  late Future<String?> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = ThumbnailUtils.generateVideoThumbnail(widget.videoPath);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _thumbnailFuture,
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
          child: const Icon(Icons.video_library, color: Colors.white24),
        );
      },
    );
  }
}
