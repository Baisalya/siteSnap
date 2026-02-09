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
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _currentFile = widget.processedFile;
  }

  /// ✅ SAVE IMAGE
  Future<void> _saveImage() async {
    if (_saving) return;

    setState(() => _saving = true);

    try {
      final savedFile =
      await GallerySaver.saveImage(_currentFile);

      if (mounted) {
        Navigator.pop(context, savedFile);
      }
    } catch (e) {
      debugPrint("Save failed: $e");
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  /// ✅ EDIT WATERMARK
  Future<void> _editWatermark() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NoteInputSheet(),
    );

    // regenerate watermark from original
    final updated = await ref
        .read(overlayViewModelProvider.notifier)
        .processImage(widget.originalFile);

    setState(() {
      _currentFile = updated;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("Preview"),
      ),

      body: Column(
        children: [
          // ================= IMAGE PREVIEW =================
          Expanded(
            child: InteractiveViewer(
              child: Image.file(
                _currentFile,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),

          // ================= ACTION BAR =================
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black,
            child: Row(
              children: [
                // EDIT BUTTON
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text("Edit"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side:
                      const BorderSide(color: Colors.white),
                    ),
                    onPressed: _editWatermark,
                  ),
                ),

                const SizedBox(width: 16),

                // SAVE BUTTON
                Expanded(
                  child: ElevatedButton.icon(
                    icon: _saving
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child:
                      CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                        : const Icon(Icons.check),
                    label: const Text("Save"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                    ),
                    onPressed:
                    _saving ? null : _saveImage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
