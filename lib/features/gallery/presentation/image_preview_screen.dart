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
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () async {
              final savedFile =
              await GallerySaver.saveImage(_currentFile);

              if (context.mounted) {
                Navigator.pop(context, savedFile);
              }
            },
          ),
        ],
      ),

      body: Column(
        children: [

          /// ================= IMAGE PREVIEW =================
          Expanded(
            child: Center(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Image.file(
                  _currentFile,

                  // ✅ VERY IMPORTANT
                  key: ValueKey(_currentFile.path),

                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),

          /// ================= EDIT BUTTON =================
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.edit),
              label: const Text('Edit Watermark Text'),
              onPressed: () async {

                /// 1️⃣ Open editor
                await showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const NoteInputSheet(),
                );

                /// 2️⃣ Recreate watermark from ORIGINAL image
                final updated = await ref
                    .read(overlayViewModelProvider.notifier)
                    .processImage(widget.originalFile);

                /// 3️⃣ Update preview
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
