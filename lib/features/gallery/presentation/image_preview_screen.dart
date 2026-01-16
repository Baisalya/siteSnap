import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/gallery_saver.dart';
import '../../overlay/presentation/overlay_viewmodel.dart';
import '../../camera/presentation/note_input_sheet.dart';

class ImagePreviewScreen extends ConsumerStatefulWidget {
  final File originalFile;
  final File processedFile;

  const ImagePreviewScreen({
    super.key,
    required this.originalFile,
    required this.processedFile,
  });

  @override
  ConsumerState<ImagePreviewScreen> createState() =>
      _ImagePreviewScreenState();
}

class _ImagePreviewScreenState
    extends ConsumerState<ImagePreviewScreen> {
  late File _currentFile;

  @override
  void initState() {
    super.initState();
    _currentFile = widget.processedFile;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () async {
              final savedFile = await GallerySaver.saveImage(_currentFile);
              Navigator.pop(context, savedFile);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // IMAGE PREVIEW
          Expanded(
            child: Image.file(
              _currentFile,
              fit: BoxFit.contain,
            ),
          ),

          // EDIT BUTTON
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.edit),
              label: const Text('Edit Watermark Text'),
              onPressed: () async {
                // 1️⃣ Open editor
                await showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const NoteInputSheet(),
                );

                // 2️⃣ Re-generate watermark from ORIGINAL
                final updated = await ref
                    .read(overlayViewModelProvider.notifier)
                    .processImage(widget.originalFile);

                // 3️⃣ FORCE UI UPDATE
                setState(() {
                  _currentFile = updated;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}
