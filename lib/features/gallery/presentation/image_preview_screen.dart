import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/gallery_saver.dart';
import '../../overlay/presentation/captured_overlay_provider.dart';
import '../../overlay/presentation/overlay_preview_state.dart';
import '../../overlay/presentation/overlay_viewmodel.dart';
import '../../camera/presentation/camera_viewmodel.dart';
import '../../camera/presentation/note_input_sheet.dart';
import '../../overlay/presentation/preview_overlay_painter.dart';
import '../../../core/utils/watermark_support_dialog.dart';

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
  final TransformationController _transformationController =
      TransformationController();
  TapDownDetails? _doubleTapDetails;

  ui.Image? _decodedImage;
  bool _saving = false;
  bool _showUI = true;
  double? _aspectRatio;

  bool _showOverlay = true;
  bool _showTextWatermark = true;

  @override
  void initState() {
    super.initState();
    _calculateAspectRatio();
  }

  void _calculateAspectRatio() {
    final image = Image.file(widget.originalFile);
    image.image.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((info, _) {
        if (mounted) {
          setState(() {
            _aspectRatio = info.image.width / info.image.height;
            _decodedImage = info.image;
          });
        }
      }),
    );
  }

  void _handleDoubleTap() {
    if (_transformationController.value != Matrix4.identity()) {
      _transformationController.value = Matrix4.identity();
    } else {
      final position = _doubleTapDetails!.localPosition;
      // Zoom in 3x
      _transformationController.value = Matrix4.identity()
        ..translate(-position.dx * 2, -position.dy * 2)
        ..scale(3.0);
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  /// ================= SAVE =================
  void _saveImage() {
    if (_saving) return;

    setState(() {
      _saving = true;
    });

    final cameraState = ref.read(cameraViewModelProvider);
    final captured = ref.read(capturedOverlayProvider);
    final live = ref.read(overlayPreviewProvider);

    final overlayData = (captured ?? live).copyWith(
      note: live.note,
      position: live.position,
    );

    // Fire and forget: Save in background
    ref.read(overlayViewModelProvider.notifier).saveCapturedImage(
          original: widget.originalFile,
          orientation:
              cameraState.captureOrientation ?? cameraState.orientation,
          overlayData: overlayData,
          showOverlay: _showOverlay,
          showWatermark: _showTextWatermark,
          decodedImage: _decodedImage,
          aspectRatio: cameraState.aspectRatio,
        );

    // Close preview immediately
    if (mounted) {
      Navigator.of(context).pop(true);
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
    final captured = ref.watch(capturedOverlayProvider);
    final live = ref.watch(overlayPreviewProvider);
    final cameraState = ref.watch(cameraViewModelProvider);

    final overlayData = (captured ?? live).copyWith(
      note: live.note,
      position: live.position,
    );

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        body: Stack(
          children: [
            /// ✅ IMAGE + OVERLAY (Full Screen & Zoomable)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showUI = !_showUI),
                onDoubleTapDown: (details) => _doubleTapDetails = details,
                onDoubleTap: _handleDoubleTap,
                behavior: HitTestBehavior.opaque,
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 1.0,
                  maxScale: 5.0,
                  child: Center(
                    child: _aspectRatio == null
                        ? const CircularProgressIndicator(
                            color: Colors.white24, strokeWidth: 2)
                        : AspectRatio(
                            aspectRatio: _aspectRatio!,
                            child: Stack(
                              children: [
                                Image.file(
                                  widget.originalFile,
                                  fit: BoxFit.fill,
                                  width: double.infinity,
                                  height: double.infinity,
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
                ),
              ),
            ),

            /// ✅ FLOATING APP BAR
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              top: _showUI ? 0 : -120,
              left: 0,
              right: 0,
              child: _buildCustomAppBar(),
            ),

            /// ✅ FLOATING ACTION BAR
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              bottom: _showUI ? 0 : -180,
              left: 0,
              right: 0,
              child: _buildBottomBarContainer(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            "Preview",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white, size: 20),
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBarContainer() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _saving ? _buildSavingBar() : _buildActionBar(),
        ),
      ),
    );
  }

  /// ================= ACTION BAR =================
  Widget _buildActionBar() {
    return ClipRRect(
      key: const ValueKey("actionBar"),
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              _buildToggleButton(
                icon: Icons.location_on_outlined,
                label: "Overlay",
                active: _showOverlay,
                onTap: () => setState(() => _showOverlay = !_showOverlay),
              ),
              const SizedBox(width: 12),
              _buildToggleButton(
                icon: Icons.text_fields_outlined,
                label: "Text",
                active: _showTextWatermark,
                onTap: () {
                  if (_showTextWatermark) {
                    showDialog(
                      context: context,
                      builder: (context) => const WatermarkSupportDialog(),
                    );
                  }
                  setState(() => _showTextWatermark = !_showTextWatermark);
                },
              ),
              const SizedBox(width: 12),
              _buildToggleButton(
                icon: Icons.edit_note_outlined,
                label: "Edit",
                active: false,
                onTap: _editWatermark,
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _saving ? null : _saveImage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.check_circle_outline, size: 20),
                label: const Text(
                  "Save",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ================= SAVING BAR =================
  Widget _buildSavingBar() {
    return ClipRRect(
      key: const ValueKey("savingBar"),
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(28),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 16),
              Text(
                "Processing & Saving...",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
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
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 22,
              color: active ? Colors.black : Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: active ? Colors.white : Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
