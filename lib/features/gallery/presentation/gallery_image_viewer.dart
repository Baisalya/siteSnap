import 'dart:io';
import 'package:flutter/material.dart';
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
  late TransformationController _transformationController;

  late int currentIndex;
  bool zoomed = false;

  @override
  void initState() {
    super.initState();

    currentIndex = widget.initialIndex;

    _pageController = PageController(
      initialPage: widget.initialIndex,
    );

    _transformationController = TransformationController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  /// ✅ DOUBLE TAP ZOOM
  void _handleDoubleTap() {
    if (zoomed) {
      _transformationController.value = Matrix4.identity();
    } else {
      _transformationController.value = Matrix4.identity()
        ..scale(2.5);
    }

    setState(() {
      zoomed = !zoomed;
    });
  }

  /// ✅ SHARE IMAGE
  Future<void> _shareImage() async {
    final file = widget.images[currentIndex];
    await Share.shareXFiles(
      [XFile(file.path)],
      text: "Shared from SiteSnap",
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          "${currentIndex + 1} / ${widget.images.length}",
          style: TextStyle(color: Colors.white),),
        actions: [
          IconButton(
            icon: const Icon(Icons.share,color: Colors.white,),
            onPressed: _shareImage,
          ),
        ],
      ),

      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.images.length,
        onPageChanged: (index) {
          setState(() {
            currentIndex = index;
            zoomed = false;
            _transformationController.value =
                Matrix4.identity();
          });
        },
        itemBuilder: (_, index) {
          return Center(
            child: GestureDetector(
              onDoubleTap: _handleDoubleTap,
              child: InteractiveViewer(
                transformationController:
                _transformationController,
                minScale: 1,
                maxScale: 4,
                child: Image.file(
                  widget.images[index],
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
