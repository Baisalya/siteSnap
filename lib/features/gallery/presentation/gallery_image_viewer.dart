import 'dart:io';
import 'package:flutter/material.dart';

class GalleryImageViewer extends StatelessWidget {
  final File file;

  const GalleryImageViewer({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Image'),
      ),
      body: Center(
        child: Image.file(
          file,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
