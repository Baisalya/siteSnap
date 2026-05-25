import 'dart:math';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:surveycam/features/camera/data/CameraState.dart';
import 'package:surveycam/features/camera/domain/camera_lens_type.dart';
import 'package:surveycam/features/overlay/presentation/overlay_settings_provider.dart';

import 'package:surveycam/features/overlay/presentation/captured_overlay_provider.dart';
import 'package:surveycam/features/overlay/presentation/overlay_preview_state.dart';
import 'package:surveycam/features/overlay/presentation/overlay_viewmodel.dart';
import 'package:surveycam/features/camera/presentation/camera_viewmodel.dart';
import 'package:surveycam/features/camera/presentation/note_input_sheet.dart';
import 'package:surveycam/features/overlay/presentation/live_overlay_painter.dart';
import 'package:surveycam/features/overlay/presentation/preview_overlay_painter.dart';
import 'package:surveycam/core/utils/watermark_support_dialog.dart';

import '../../overlay/domain/overlay_model.dart';
import '../../overlay/domain/overlay_settings.dart';

class ImagePreviewScreen extends ConsumerStatefulWidget {
  final File originalFile;
  final File processedFile;
  const ImagePreviewScreen({
    super.key,
    required this.originalFile,
    required this.processedFile,
  });

  @override
  ConsumerState<ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends ConsumerState<ImagePreviewScreen> {
  final TransformationController _transformationController =
      TransformationController();
  TapDownDetails? _doubleTapDetails;

  bool _saving = false;
  bool _showUI = true;
  double? _aspectRatio;

  bool _showOverlay = true;
  bool _showTextWatermark = true;
  ui.Image? _previewImage;
  PictureInfo? _svgPicture;
  DeviceOrientation? _captureOrientation;
  CameraAspectRatio? _captureAspectRatio;
  CameraLensType? _captureLens;

  @override
  void initState() {
    super.initState();
    _capturePreviewState();
    _loadPreviewImage();
    _loadSvg();
  }

  void _loadPreviewImage() async {
    try {
      final bytes = await widget.originalFile.readAsBytes();
      // Use instantiateImageCodec with targetWidth/Height if we want to downsample for preview speed,
      // but here we want full quality for CustomPaint. Still, we can do it in background.
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();

      if (!mounted) {
        frame.image.dispose();
        return;
      }

      setState(() {
        _previewImage?.dispose();
        _previewImage = frame.image;
      });
    } catch (e) {
      debugPrint("Error loading preview image: $e");
    }
  }

  void _loadSvg() async {
    final pic = await PreviewOverlayPainter.loadSvg();

    if (!mounted) return;

    setState(() {
      _svgPicture = pic;
    });
  }

  void _capturePreviewState() {
    final cameraState = ref.read(cameraViewModelProvider);
    _captureOrientation =
        cameraState.captureOrientation ?? cameraState.orientation;
    _captureAspectRatio = cameraState.aspectRatio;
    _captureLens = cameraState.captureLens ?? cameraState.currentLens;
    _aspectRatio = _captureAspectRatio!.forOrientation(_captureOrientation!);
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
    _previewImage?.dispose();
    super.dispose();
  }

  /// ================= SAVE =================
  void _saveImage() {
    if (_saving) return;

    final cameraState = ref.read(cameraViewModelProvider);
    final captured = ref.read(capturedOverlayProvider);
    final live = ref.read(overlayPreviewProvider);

    final overlayData = (captured ?? live).copyWith(
      note: live.note,
      position: live.position,
    );

    final isMirror =
        (_captureLens ?? cameraState.captureLens) == CameraLensType.front;
    final orientation = _captureOrientation ??
        cameraState.captureOrientation ??
        cameraState.orientation;
    final aspectRatio = _captureAspectRatio ?? cameraState.aspectRatio;

    // Return the save future so the camera screen can keep the gallery current
    // while the final watermarked file is produced.
    final saveFuture =
        ref.read(overlayViewModelProvider.notifier).saveCapturedImage(
              original: widget.originalFile,
              orientation: orientation,
              overlayData: overlayData,
              showOverlay: _showOverlay,
              showWatermark: _showTextWatermark,
              aspectRatio: aspectRatio,
              mirror: isMirror,
            );

    if (mounted) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(saveFuture);
    }
  }

  /// ================= SHARE =================
  Future<void> _shareImage() async {
    if (_saving) return;

    setState(() {
      _saving = true;
    });

    try {
      final cameraState = ref.read(cameraViewModelProvider);
      final captured = ref.read(capturedOverlayProvider);
      final live = ref.read(overlayPreviewProvider);

      final overlayData = (captured ?? live).copyWith(
        note: live.note,
        position: live.position,
      );

      final isMirror =
          (_captureLens ?? cameraState.captureLens) == CameraLensType.front;
      final orientation = _captureOrientation ??
          cameraState.captureOrientation ??
          cameraState.orientation;
      final aspectRatio = _captureAspectRatio ?? cameraState.aspectRatio;

      // Process image with overlays
      final bytes =
          await ref.read(overlayViewModelProvider.notifier).processImage(
                widget.originalFile,
                orientation,
                overlayData: overlayData,
                showOverlay: _showOverlay,
                showWatermark: _showTextWatermark,
                aspectRatio: aspectRatio,
                mirror: isMirror,
              );

      // Save to temp file for sharing
      final tempDir = await getTemporaryDirectory();
      final tempPath = p.join(
        tempDir.path,
        "shared_${DateTime.now().millisecondsSinceEpoch}.jpg",
      );
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(bytes);

      if (!mounted) return;

      // Share
      await Share.shareXFiles(
        [XFile(tempPath)],
        text: "Shared from SurveyCam 📷",
      );
    } catch (e) {
      debugPrint("Share error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to share image")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
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
    final captured = ref.watch(capturedOverlayProvider);
    final live = ref.watch(overlayPreviewProvider);
    final cameraState = ref.watch(cameraViewModelProvider);
    final settings = ref.watch(overlaySettingsProvider);

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
                    child: _aspectRatio == null || _previewImage == null
                        ? const CircularProgressIndicator(
                            color: Colors.white24, strokeWidth: 2)
                        : AspectRatio(
                            aspectRatio: _aspectRatio!,
                            child: CustomPaint(
                              painter: _CapturedPhotoPreviewPainter(
                                image: _previewImage!,
                                data: overlayData,
                                showOverlay: _showOverlay,
                                showWatermark: _showTextWatermark,
                                orientation: _captureOrientation ??
                                    cameraState.captureOrientation ??
                                    cameraState.orientation,
                                aspectRatio: _captureAspectRatio ??
                                    cameraState.aspectRatio,
                                mirror:
                                    (_captureLens ?? cameraState.captureLens) ==
                                        CameraLensType.front,
                                svgPicture: _svgPicture,
                                settings: settings,
                              ),
                              child: const SizedBox.expand(),
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
        child: _buildActionBar(),
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
              const SizedBox(width: 12),
              _buildToggleButton(
                icon: Icons.share_outlined,
                label: "Share",
                active: false,
                onTap: _shareImage,
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _saveImage,
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
              color:
                  active ? Colors.white : Colors.white.withValues(alpha: 0.1),
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
              color:
                  active ? Colors.white : Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapturedPhotoPreviewPainter extends CustomPainter {
  final ui.Image image;
  final OverlayData data;
  final bool showOverlay;
  final bool showWatermark;
  final DeviceOrientation orientation;
  final CameraAspectRatio aspectRatio;
  final bool mirror;
  final PictureInfo? svgPicture;
  final OverlaySettings settings;

  _CapturedPhotoPreviewPainter({
    required this.image,
    required this.data,
    required this.showOverlay,
    required this.showWatermark,
    required this.orientation,
    required this.aspectRatio,
    required this.mirror,
    required this.svgPicture,
    required this.settings,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width == 0 || size.height == 0) return;

    final srcRect = _sourceCropRect();
    final isLandscape = orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight;
    final outputWidth = isLandscape ? srcRect.height : srcRect.width;
    final outputHeight = isLandscape ? srcRect.width : srcRect.height;

    canvas.save();
    canvas.scale(size.width / outputWidth, size.height / outputHeight);
    _applySavedOrientation(canvas, outputWidth, outputHeight);

    if (mirror) {
      canvas.save();
      canvas.translate(srcRect.width, 0);
      canvas.scale(-1, 1);
      _drawImage(canvas, srcRect);
      canvas.restore();
    } else {
      _drawImage(canvas, srcRect);
    }

    if (showOverlay) {
      final overlayPainter =
          LiveOverlayPainter(data, orientation, settings: settings);
      overlayPainter.paint(canvas, Size(srcRect.width, srcRect.height));
    }

    if (showWatermark && svgPicture != null) {
      _drawWatermark(canvas, srcRect);
    }

    canvas.restore();
  }

  Rect _sourceCropRect() {
    final srcW = image.width.toDouble();
    final srcH = image.height.toDouble();
    final targetRatio = aspectRatio.portraitValue;
    final currentRatio = srcW / srcH;

    if (currentRatio > targetRatio) {
      final newW = srcH * targetRatio;
      return Rect.fromCenter(
        center: Offset(srcW / 2, srcH / 2),
        width: newW,
        height: srcH,
      );
    }

    if (currentRatio < targetRatio) {
      final newH = srcW / targetRatio;
      return Rect.fromCenter(
        center: Offset(srcW / 2, srcH / 2),
        width: srcW,
        height: newH,
      );
    }

    return Rect.fromLTWH(0, 0, srcW, srcH);
  }

  void _drawImage(Canvas canvas, Rect srcRect) {
    canvas.drawImageRect(
      image,
      srcRect,
      Rect.fromLTWH(0, 0, srcRect.width, srcRect.height),
      Paint()..filterQuality = ui.FilterQuality.high,
    );
  }

  void _applySavedOrientation(Canvas canvas, double w, double h) {
    switch (orientation) {
      case DeviceOrientation.portraitUp:
        break;
      case DeviceOrientation.portraitDown:
        canvas.translate(w, h);
        canvas.rotate(pi);
        break;
      case DeviceOrientation.landscapeLeft:
        canvas.translate(w, 0);
        canvas.rotate(pi / 2);
        break;
      case DeviceOrientation.landscapeRight:
        canvas.translate(0, h);
        canvas.rotate(-pi / 2);
        break;
    }
  }

  void _undoOrientationForWatermark(
    Canvas canvas,
    double w,
    double h,
  ) {
    switch (orientation) {
      case DeviceOrientation.portraitUp:
        break;
      case DeviceOrientation.portraitDown:
        canvas.translate(w, h);
        canvas.rotate(pi);
        break;
      case DeviceOrientation.landscapeLeft:
        canvas.translate(0, h);
        canvas.rotate(-pi / 2);
        break;
      case DeviceOrientation.landscapeRight:
        canvas.translate(w, 0);
        canvas.rotate(pi / 2);
        break;
    }
  }

  void _drawWatermark(Canvas canvas, Rect srcRect) {
    canvas.save();
    _undoOrientationForWatermark(canvas, srcRect.width, srcRect.height);

    final contentW = srcRect.width;
    final baseSize = min(srcRect.width, srcRect.height);
    final padding = contentW * 0.04;

    final textPainter = TextPainter(
      text: TextSpan(
        text: "SurveyCam",
        style: TextStyle(
          color: Colors.white,
          fontSize: baseSize * 0.045,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              blurRadius: 6,
              color: Colors.black.withValues(alpha: 0.5),
              offset: const Offset(1, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final svgSize = textPainter.height;
    const spacing = 10.0;
    final totalWidth = svgSize + spacing + textPainter.width;
    final isLandscape = orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight;

    final dx = isLandscape ? padding : contentW - totalWidth - padding;
    final dy = padding;

    canvas.save();
    canvas.translate(dx, dy);
    final scale = svgSize / svgPicture!.size.height;
    canvas.scale(scale, scale);
    canvas.drawPicture(svgPicture!.picture);
    canvas.restore();

    textPainter.paint(canvas, Offset(dx + svgSize + spacing, dy));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CapturedPhotoPreviewPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.data != data ||
        oldDelegate.showOverlay != showOverlay ||
        oldDelegate.showWatermark != showWatermark ||
        oldDelegate.orientation != orientation ||
        oldDelegate.aspectRatio != aspectRatio ||
        oldDelegate.mirror != mirror ||
        oldDelegate.svgPicture != svgPicture ||
        oldDelegate.settings != settings;
  }
}
