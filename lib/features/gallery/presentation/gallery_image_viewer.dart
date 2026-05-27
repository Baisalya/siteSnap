import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:share_plus/share_plus.dart';
import 'package:surveycam/features/gallery/data/sitesnap_gallery_repository.dart';
import 'package:surveycam/features/gallery/presentation/video_player_screen.dart';

class GalleryImageViewer extends ConsumerStatefulWidget {
  final List<File> images;
  final int initialIndex;

  const GalleryImageViewer({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  @override
  ConsumerState<GalleryImageViewer> createState() => _GalleryImageViewerState();
}

class _GalleryImageViewerState extends ConsumerState<GalleryImageViewer> {
  late PageController _pageController;
  late int currentIndex;

  bool _showUI = true;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;

    _pageController = PageController(
      initialPage: currentIndex,
    );
  }

  /// ✅ SHARE
  Future<void> _shareImage() async {
    final file =
        _displayImages(ref.read(galleryProcessingProvider))[currentIndex];

    if (!file.existsSync()) return;

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: "Shared from SurveyCam 📷",
      ),
    );
  }

  List<File> _displayImages(Map<String, GalleryProcessingItem> processing) {
    return widget.images.map((file) {
      return processing[file.path]?.processedFile ?? file;
    }).toList(growable: false);
  }

  /// 🎯 Toggle UI (like real gallery apps)
  void _toggleUI() {
    setState(() {
      _showUI = !_showUI;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final processing = ref.watch(galleryProcessingProvider);
    final displayImages = _displayImages(processing);

    return Scaffold(
      backgroundColor: Colors.black,

      /// 🔥 APP BAR (auto hide)
      appBar: _showUI
          ? AppBar(
              backgroundColor: Colors.black,
              elevation: 0,
              title: Text(
                "${currentIndex + 1} / ${displayImages.length}",
                style: const TextStyle(color: Colors.white),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.share, color: Colors.white),
                  onPressed: _shareImage,
                ),
              ],
            )
          : null,

      body: GestureDetector(
        onTap: () {
          final file = displayImages[currentIndex];
          final isVideo = file.path.toLowerCase().endsWith('.mp4') ||
              file.path.toLowerCase().endsWith('.mov');
          if (isVideo) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => VideoPlayerScreen(file: file),
              ),
            );
          } else {
            _toggleUI();
          }
        },
        child: Stack(
          children: [
            /// 📷 PROFESSIONAL GALLERY
            PhotoViewGallery.builder(
              pageController: _pageController,
              itemCount: displayImages.length,
              onPageChanged: (index) {
                setState(() {
                  currentIndex = index;
                });
              },
              builder: (context, index) {
                final originalFile = widget.images[index];
                final file = displayImages[index];
                final processingItem = processing[originalFile.path];
                final isVideo = file.path.toLowerCase().endsWith('.mp4') ||
                    file.path.toLowerCase().endsWith('.mov');

                if (isVideo) {
                  return PhotoViewGalleryPageOptions.customChild(
                    child: const Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(Icons.video_library,
                            color: Colors.white24, size: 100),
                        Icon(Icons.play_circle_outline,
                            color: Colors.white, size: 80),
                      ],
                    ),
                    initialScale: PhotoViewComputedScale.contained,
                    heroAttributes:
                        PhotoViewHeroAttributes(tag: originalFile.path),
                  );
                }

                return PhotoViewGalleryPageOptions.customChild(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 650),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: Image.file(
                            file,
                            key: ValueKey(file.path),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      if (processingItem?.isProcessing ?? false)
                        const Positioned(
                          left: 24,
                          right: 24,
                          bottom: 86,
                          child: _ViewerProcessingPill(
                            icon: _ViewerProcessingIcon.progress,
                            text: 'Raw photo saved. Adding overlay...',
                          ),
                        )
                      else if (processingItem?.isComplete ?? false)
                        const Positioned(
                          left: 24,
                          right: 24,
                          bottom: 86,
                          child: _ViewerProcessingPill(
                            icon: _ViewerProcessingIcon.done,
                            text: 'Overlay applied',
                          ),
                        )
                      else if (processingItem?.failed ?? false)
                        const Positioned(
                          left: 24,
                          right: 24,
                          bottom: 86,
                          child: _ViewerProcessingPill(
                            icon: _ViewerProcessingIcon.warning,
                            text: 'Raw photo saved. Overlay failed.',
                          ),
                        ),
                    ],
                  ),

                  /// 🔥 PERFECT ZOOM CONFIG
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 3,
                  initialScale: PhotoViewComputedScale.contained,
                  heroAttributes: PhotoViewHeroAttributes(
                    tag: originalFile.path,
                  ),
                );
              },
              scrollPhysics: const BouncingScrollPhysics(),
              backgroundDecoration: const BoxDecoration(color: Colors.black),
            ),

            /// 🔻 BOTTOM CONTROLS (optional)
            if (_showUI)
              const Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    Text(
                      "Tap to hide UI",
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _ViewerProcessingIcon { progress, done, warning }

class _ViewerProcessingPill extends StatelessWidget {
  final _ViewerProcessingIcon icon;
  final String text;

  const _ViewerProcessingPill({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIcon(),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    switch (icon) {
      case _ViewerProcessingIcon.progress:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: Colors.white,
          ),
        );
      case _ViewerProcessingIcon.done:
        return const Icon(
          Icons.check_circle_outline,
          color: Colors.lightGreenAccent,
          size: 18,
        );
      case _ViewerProcessingIcon.warning:
        return const Icon(
          Icons.error_outline,
          color: Colors.orangeAccent,
          size: 18,
        );
    }
  }
}
