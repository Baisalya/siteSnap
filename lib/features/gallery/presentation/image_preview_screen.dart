import 'dart:async';
import 'dart:convert';
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

enum _PreviewBusyAction { save, share }

class _ImagePreviewScreenState extends ConsumerState<ImagePreviewScreen> {
  // 🔥 Increased decode width to 3200 to significantly reduce "softness" in preview.
  // This provides much more "structure" and detail when viewing the captured photo.
  static const int _previewDecodeWidth = 3200;

  final TransformationController _transformationController =
      TransformationController();
  TapDownDetails? _doubleTapDetails;

  _PreviewBusyAction? _busyAction;
  bool _showUI = true;
  double? _aspectRatio;

  bool _showOverlay = true;
  bool _showTextWatermark = true;
  ui.Image? _previewImage;
  ui.Image? _customLogoImage;
  String? _loadedCustomLogoPath;
  PictureInfo? _svgPicture;
  DeviceOrientation? _captureOrientation;
  CameraAspectRatio? _captureAspectRatio;
  CameraLensType? _captureLens;
  Timer? _prepareSaveTimer;
  String? _preparedSaveKey;
  String?
      _scheduledSignature; // 🔥 Track the signature currently being prepared
  Future<Uint8List>? _preparedSaveFuture;

  bool get _saving => _busyAction != null;

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

      // Phase 1: Super fast decode (low-res) for instant visual feedback
      // 800px is enough for a sharp-looking thumbnail while the high-res loads.
      final fastCodec = await ui.instantiateImageCodec(bytes, targetWidth: 800);
      final fastFrame = await fastCodec.getNextFrame();

      if (!mounted) {
        fastFrame.image.dispose();
        return;
      }

      setState(() {
        _previewImage = fastFrame.image;
      });

      // Phase 2: High resolution decode for maximum "structure" and detail
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: _previewDecodeWidth,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();

      if (!mounted) {
        frame.image.dispose();
        return;
      }

      setState(() {
        final old = _previewImage;
        _previewImage = frame.image;
        // Dispose the low-res version once high-res is ready
        if (old != _previewImage) old?.dispose();
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

  void _loadCustomLogo(String? path) async {
    _loadedCustomLogoPath = path;
    if (path == null || path.isEmpty) {
      setState(() {
        _customLogoImage?.dispose();
        _customLogoImage = null;
      });
      return;
    }

    try {
      final file = File(path);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();

      if (!mounted || _loadedCustomLogoPath != path) {
        frame.image.dispose();
        return;
      }

      setState(() {
        _customLogoImage?.dispose();
        _customLogoImage = frame.image;
      });
    } catch (e) {
      debugPrint("Error loading custom watermark logo: $e");
    }
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

  String _preparedSaveSignature({
    required CameraState cameraState,
    required OverlayData overlayData,
    required OverlaySettings settings,
  }) {
    final orientation = _captureOrientation ??
        cameraState.captureOrientation ??
        cameraState.orientation;
    final aspectRatio = _captureAspectRatio ?? cameraState.aspectRatio;
    final mirror =
        (_captureLens ?? cameraState.captureLens) == CameraLensType.front;

    return jsonEncode({
      'path': widget.originalFile.path,
      'overlayData': overlayData.toJson(),
      'settings': settings.toJson(),
      'showOverlay': _showOverlay,
      'showWatermark': _showTextWatermark,
      'orientation': orientation.index,
      'aspectRatio': aspectRatio.index,
      'mirror': mirror,
    });
  }

  void _schedulePreparedSave({
    required String signature,
    required CameraState cameraState,
    required OverlayData overlayData,
    required OverlaySettings settings,
  }) {
    // 🔥 OPTIMIZATION: If we are already saving, or have finished this signature,
    // or a timer is already counting down for this EXACT signature, don't restart it.
    // This prevents the "softness" of the UI (renders) from delaying the background processing.
    if (_saving ||
        _preparedSaveKey == signature ||
        _scheduledSignature == signature) {
      return;
    }

    _prepareSaveTimer?.cancel();
    _scheduledSignature = signature;

    // Reduced delay from 220ms to 80ms for much more aggressive "instant" feel.
    _prepareSaveTimer = Timer(const Duration(milliseconds: 80), () {
      if (!mounted || _saving) return;

      final orientation = _captureOrientation ??
          cameraState.captureOrientation ??
          cameraState.orientation;
      final aspectRatio = _captureAspectRatio ?? cameraState.aspectRatio;
      final mirror =
          (_captureLens ?? cameraState.captureLens) == CameraLensType.front;

      _preparedSaveKey = signature;
      _preparedSaveFuture = ref
          .read(overlayViewModelProvider.notifier)
          .processImage(
            widget.originalFile,
            orientation,
            overlayData: overlayData,
            showOverlay: _showOverlay,
            showWatermark: _showTextWatermark,
            aspectRatio: aspectRatio,
            mirror: mirror,
            settingsOverride: settings,
          )
          .catchError((Object error, StackTrace stackTrace) {
        debugPrint("Prepared save failed: $error");
        return Uint8List(0);
      });
    });
  }

  @override
  void dispose() {
    _prepareSaveTimer?.cancel();
    _transformationController.dispose();
    _previewImage?.dispose();
    _customLogoImage?.dispose();
    super.dispose();
  }

  /// ================= SAVE =================
  Future<void> _saveImage() async {
    if (_saving) return;

    // 🔥 Trigger UI feedback immediately
    HapticFeedback.mediumImpact();
    setState(() {
      _busyAction = _PreviewBusyAction.save;
      _showUI = true;
    });

    final cameraState = ref.read(cameraViewModelProvider);
    final captured = ref.read(capturedOverlayProvider);
    final live = ref.read(overlayPreviewProvider);
    final settings = ref.read(overlaySettingsProvider);

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
    final saveSignature = _preparedSaveSignature(
      cameraState: cameraState,
      overlayData: overlayData,
      settings: settings,
    );

    // Check if we have a background-prepared future for this specific image state
    final preparedSaveFuture =
        _preparedSaveKey == saveSignature ? _preparedSaveFuture : null;

    final saveFuture = preparedSaveFuture == null
        ? ref.read(overlayViewModelProvider.notifier).saveCapturedImage(
              original: widget.originalFile,
              orientation: orientation,
              overlayData: overlayData,
              showOverlay: _showOverlay,
              showWatermark: _showTextWatermark,
              aspectRatio: aspectRatio,
              mirror: isMirror,
            )
        : ref.read(overlayViewModelProvider.notifier).savePreparedCapturedImage(
              original: widget.originalFile,
              preparedBytes: preparedSaveFuture,
              overlayData: overlayData,
              settings: settings,
              orientation: orientation,
              showOverlay: _showOverlay,
              showWatermark: _showTextWatermark,
              mirror: isMirror,
            );

    // Give enough time for the "Checkmark" animation to be visible.
    // Increased to 1100ms to give background processing more time to finish
    // before the screen pops, ensuring the gallery gets the overlay version instantly.
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    if (mounted) {
      Navigator.of(context).pop(saveFuture);
    }
  }

  /// ================= SHARE =================
  Future<void> _shareImage() async {
    if (_saving) return;

    HapticFeedback.lightImpact();
    setState(() {
      _busyAction = _PreviewBusyAction.share;
    });

    try {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;

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
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempPath)],
          text: "Shared from SurveyCam 📷",
        ),
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
          _busyAction = null;
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
    if (_loadedCustomLogoPath != settings.activeWatermarkLogoPath) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadCustomLogo(settings.activeWatermarkLogoPath);
      });
    }

    final overlayData = (captured ?? live).copyWith(
      note: live.note,
      position: live.position,
    );
    final preparedSaveSignature = _preparedSaveSignature(
      cameraState: cameraState,
      overlayData: overlayData,
      settings: settings,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _schedulePreparedSave(
        signature: preparedSaveSignature,
        cameraState: cameraState,
        overlayData: overlayData,
        settings: settings,
      );
    });

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
                        ? const SizedBox.shrink()
                        : AspectRatio(
                            aspectRatio: _aspectRatio!,
                            child: _previewImage == null
                                ? const SizedBox.shrink()
                                : CustomPaint(
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
                                      mirror: (_captureLens ??
                                              cameraState.captureLens) ==
                                          CameraLensType.front,
                                      svgPicture: _svgPicture,
                                      customLogo: _customLogoImage,
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
            if (_busyAction == _PreviewBusyAction.save)
              const Positioned.fill(
                child: _PhotoSaveFeedbackOverlay(),
              ),

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
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
                child: child,
              ),
            );
          },
          child: switch (_busyAction) {
            _PreviewBusyAction.save => _buildSavingBar(),
            _PreviewBusyAction.share => _buildSharingBar(),
            null => _buildActionBar(),
          },
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF12B76A).withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.28),
              width: 0.6,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF12B76A).withValues(alpha: 0.32),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: _SavePreparingIcon(),
              ),
              SizedBox(width: 14),
              Flexible(
                child: Text(
                  "Saving photo...",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              SizedBox(width: 14),
              Text(
                "Background task",
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ================= SHARING BAR =================
  Widget _buildSharingBar() {
    return ClipRRect(
      key: const ValueKey("sharingBar"),
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.46),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: _SharePreparingIcon(),
              ),
              const SizedBox(width: 14),
              const Flexible(
                child: Text(
                  "Preparing share...",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                "Opening options",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.64),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
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

class _SharePreparingIcon extends StatefulWidget {
  const _SharePreparingIcon();

  @override
  State<_SharePreparingIcon> createState() => _SharePreparingIconState();
}

class _SharePreparingIconState extends State<_SharePreparingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.9, end: 1.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        const CircularProgressIndicator(
          strokeWidth: 2.2,
          color: Colors.white,
        ),
        ScaleTransition(
          scale: _scale,
          child: const Icon(
            Icons.ios_share_outlined,
            color: Colors.white,
            size: 13,
          ),
        ),
      ],
    );
  }
}

class _SavePreparingIcon extends StatefulWidget {
  const _SavePreparingIcon();

  @override
  State<_SavePreparingIcon> createState() => _SavePreparingIconState();
}

class _SavePreparingIconState extends State<_SavePreparingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 0.92 + (_controller.value * 0.14);
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.check_rounded,
          color: Colors.white,
          size: 18,
        ),
      ),
    );
  }
}

class _PhotoSaveFeedbackOverlay extends StatelessWidget {
  const _PhotoSaveFeedbackOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          final pulseOpacity = (1 - value).clamp(0.0, 1.0);
          final pulseScale = 0.72 + (value * 1.2);

          return Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF12B76A)
                      .withValues(alpha: 0.18 + (pulseOpacity * 0.1)),
                ),
              ),
              Center(
                child: Transform.scale(
                  scale: pulseScale,
                  child: Opacity(
                    opacity: pulseOpacity,
                    child: Container(
                      width: 132,
                      height: 132,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.72),
                          width: 2.6,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: const Color(0xFF12B76A),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF12B76A).withValues(alpha: 0.46),
                        blurRadius: 28,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
            ],
          );
        },
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
  final ui.Image? customLogo;
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
    required this.customLogo,
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

    if (showWatermark && (svgPicture != null || customLogo != null)) {
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

    final brandText = settings.activeWatermarkText.trim();
    final hasText = brandText.isNotEmpty;
    final hasLogo = settings.activeWatermarkShowLogo;
    final textPainter = TextPainter(
      text: TextSpan(
        text: brandText,
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

    final double logoSize =
        hasLogo ? (hasText ? textPainter.height : baseSize * 0.06) : 0;
    final double spacing = hasLogo && hasText ? 10.0 : 0.0;
    final double totalWidth =
        logoSize + spacing + (hasText ? textPainter.width : 0);
    if (totalWidth <= 0) {
      canvas.restore();
      return;
    }
    final isLandscape = orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight;

    final dx = isLandscape ? padding : contentW - totalWidth - padding;
    final dy = padding;

    if (hasLogo) {
      canvas.save();
      canvas.translate(dx, dy);
      if (customLogo != null) {
        canvas.drawImageRect(
          customLogo!,
          Rect.fromLTWH(
            0,
            0,
            customLogo!.width.toDouble(),
            customLogo!.height.toDouble(),
          ),
          Rect.fromLTWH(0, 0, logoSize, logoSize),
          Paint()..filterQuality = ui.FilterQuality.high,
        );
      } else if (svgPicture != null) {
        final scale = logoSize / svgPicture!.size.height;
        canvas.scale(scale, scale);
        canvas.drawPicture(svgPicture!.picture);
      }
      canvas.restore();
    }

    if (hasText) {
      textPainter.paint(canvas, Offset(dx + logoSize + spacing, dy));
    }
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
        oldDelegate.customLogo != customLogo ||
        oldDelegate.settings != settings;
  }
}
