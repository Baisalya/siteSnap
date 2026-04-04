import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/gallery_saver.dart';
import '../../overlay/presentation/overlay_preview_state.dart';
import '../../overlay/presentation/overlay_viewmodel.dart';
import '../../camera/presentation/camera_viewmodel.dart';
import '../../camera/presentation/note_input_sheet.dart';
import '../../overlay/presentation/preview_overlay_painter.dart';

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

  bool _saving = false;
  bool _hideUI = false;

  bool _showOverlay = true;
  bool _showTextWatermark = true;

  /// ================= SAVE =================
  Future<void> _saveImage() async {
    if (_saving) return;

    setState(() {
      _saving = true;
      _hideUI = true;
    });

    try {
      final cameraState = ref.read(cameraViewModelProvider);

      final finalFile = await ref
          .read(overlayViewModelProvider.notifier)
          .processImage(
        widget.originalFile,
        cameraState.captureOrientation ??
            cameraState.orientation,
        showOverlay: _showOverlay,
        showWatermark: _showTextWatermark,
      );

      final savedFile =
      await GallerySaver.saveImage(finalFile);

      if (mounted) {
        Navigator.pop(context, savedFile);
      }
    } catch (e) {
      debugPrint("Save failed: $e");
      if (mounted) {
        setState(() {
          _saving = false;
          _hideUI = false;
        });
      }
    }
  }

  /// ================= EDIT =================
  Future<void> _editWatermark() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NoteInputSheet(),
    );

    if (!mounted) return;
    setState(() {});
  }

  /// ================= UI =================
  @override
  Widget build(BuildContext context) {
    final overlayData = ref.watch(overlayPreviewProvider);
    final cameraState = ref.watch(cameraViewModelProvider);

    return Scaffold(
      backgroundColor: Colors.black,

      appBar: _hideUI
          ? null
          : AppBar(
        backgroundColor: Colors.black,
        title: const Text("Preview"),
      ),

      body: Column(
        children: [

          /// IMAGE + OVERLAY
          Expanded(
            child: InteractiveViewer(
              child: Stack(
                children: [
                  Image.file(
                    widget.originalFile,
                    fit: BoxFit.contain,
                    width: double.infinity,
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: PreviewOverlayPainter(
                          data: overlayData,
                          showOverlay: _showOverlay,
                          showWatermark: _showTextWatermark,
                          orientation:
                          cameraState.captureOrientation ??
                              cameraState.orientation,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          /// 🔥 ANIMATED SWITCH (KEY PART)
          // 🔥 FIXED HEIGHT (adjust if needed)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(animation),
                  child: FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                );
              },
              child: _hideUI
                  ? _buildSavingBar()
                  : _buildActionBar(),
            ),
                ],
      ),
    );
  }

  /// ================= ACTION BAR =================
  Widget _buildActionBar() {
    return Container(
      key: const ValueKey("actionBar"),
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 14, // ✅ SAME as saving bar
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          _buildToggleButton(
            icon: Icons.location_on,
            label: "Overlay",
            active: _showOverlay,
            onTap: () {
              setState(() => _showOverlay = !_showOverlay);
            },
          ),
          const SizedBox(width: 8),
          _buildToggleButton(
            icon: Icons.text_fields,
            label: "Text",
            active: _showTextWatermark,
            onTap: () {
              setState(() =>
              _showTextWatermark = !_showTextWatermark);
            },
          ),
          const SizedBox(width: 8),
          _buildToggleButton(
            icon: Icons.tune,
            label: "Edit",
            active: false,
            onTap: _editWatermark,
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _saving ? null : _saveImage,
            icon: _saving
                ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.black,
              ),
            )
                : const Icon(Icons.download),
            label: const Text("Save"),
          ),
        ],
      ),
    );
  }
  /// ================= SAVING BAR =================
  Widget _buildSavingBar() {
    return Container(
      key: const ValueKey("savingBar"),
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14, // ✅ SAME HEIGHT
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            "Saving...",
            style: TextStyle(color: Colors.white),
          ),
          const Spacer(),
          const Icon(Icons.check_circle_outline,
              color: Colors.white54),
        ],
      ),
    );
  }
  /// ================= TOGGLE BUTTON =================
  Widget _buildToggleButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? Colors.white
              : Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center( // 🔥 IMPORTANT FIX
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center, // ✅ FIX
            children: [
              Icon(
                icon,
                size: 20,
                color: active ? Colors.black : Colors.white,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color:
                  active ? Colors.black : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}