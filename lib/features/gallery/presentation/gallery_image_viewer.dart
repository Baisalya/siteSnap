import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:share_plus/share_plus.dart';

class GalleryImageViewer extends StatefulWidget {
  final List<File> images;
  final int initialIndex;

  const GalleryImageViewer({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  @override
  State<GalleryImageViewer> createState() =>
      _GalleryImageViewerState();
}

class _GalleryImageViewerState extends State<GalleryImageViewer> {
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
    final file = widget.images[currentIndex];

    if (!file.existsSync()) return;

    await Share.shareXFiles(
      [XFile(file.path)],
      text: "Shared from SurveyCam 📷",
    );
  }

  /// 🎯 Toggle UI (like real gallery apps)
  void _toggleUI() {
    setState(() {
      _showUI = !_showUI;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      /// 🔥 APP BAR (auto hide)
      appBar: _showUI
          ? AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          "${currentIndex + 1} / ${widget.images.length}",
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
        onTap: _toggleUI,

        child: Stack(
          children: [

            /// 📷 PROFESSIONAL GALLERY
            PhotoViewGallery.builder(
              pageController: _pageController,
              itemCount: widget.images.length,

              onPageChanged: (index) {
                setState(() {
                  currentIndex = index;
                });
              },

              builder: (context, index) {
                final file = widget.images[index];

                return PhotoViewGalleryPageOptions(
                  imageProvider: FileImage(file),

                  /// 🔥 PERFECT ZOOM CONFIG
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 3,

                  initialScale: PhotoViewComputedScale.contained,

                  heroAttributes: PhotoViewHeroAttributes(
                    tag: file.path,
                  ),
                );
              },

              scrollPhysics: const BouncingScrollPhysics(),
              backgroundDecoration:
              const BoxDecoration(color: Colors.black),
            ),

            /// 🔻 BOTTOM CONTROLS (optional)
            if (_showUI)
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Column(
                  children: const [
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