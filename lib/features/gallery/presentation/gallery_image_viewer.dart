import 'dart:io';
import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;

    _pageController = PageController(
      initialPage: widget.initialIndex,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          "${currentIndex + 1} / ${widget.images.length}",
        ),
      ),

      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.images.length,
        onPageChanged: (index) {
          setState(() {
            currentIndex = index;
          });
        },
        itemBuilder: (_, index) {
          return Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image.file(
                widget.images[index],
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          );
        },
      ),
    );
  }
}
