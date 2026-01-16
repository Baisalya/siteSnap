import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../gallery/presentation/image_preview_screen.dart';
import '../../gallery/presentation/last_image_provider.dart';
import '../../overlay/presentation/overlay_viewmodel.dart';
import '../domain/camera_lens_type.dart';

final cameraViewModelProvider =
StateNotifierProvider<CameraViewModel, CameraState>((ref) {
  return CameraViewModel(ref);
});

/// ✅ SINGLE CameraState (ONLY ONE)
class CameraState {
  final bool isReady;
  final CameraController? controller;
  final bool flashOn;
  final CameraLensType currentLens;

  const CameraState({
    required this.isReady,
    this.controller,
    this.flashOn = false,
    this.currentLens = CameraLensType.normal, // ✅ default
  });

  CameraState copyWith({
    bool? isReady,
    CameraController? controller,
    bool? flashOn,
    CameraLensType? currentLens,
  }) {
    return CameraState(
      isReady: isReady ?? this.isReady,
      controller: controller ?? this.controller,
      flashOn: flashOn ?? this.flashOn,
      currentLens: currentLens ?? this.currentLens,
    );
  }
}

class CameraViewModel extends StateNotifier<CameraState> {
  final Ref ref;

  CameraViewModel(this.ref)
      : super(const CameraState(isReady: false)) {
    _init();
  }

  Future<void> _init() async {
    final repo = ref.read(cameraRepositoryProvider);

    await repo.initialize(CameraLensType.normal);

    state = state.copyWith(
      isReady: true,
      controller: repo.controller,
      currentLens: CameraLensType.normal,
    );
  }


  /// 📸 Capture image with watermark
  Future<void> capture(BuildContext context) async {
    final repo = ref.read(cameraRepositoryProvider);

    // 1️⃣ Capture original
    final originalPath = await repo.takePicture();
    final originalFile = File(originalPath);

    // 2️⃣ Create initial watermarked image
    final processedFile =
    await ref.read(overlayViewModelProvider.notifier)
        .processImage(originalFile);

    // 3️⃣ Open preview with BOTH files
    if (context.mounted) {
      final result = await Navigator.push<File>(
        context,
        MaterialPageRoute(
          builder: (_) => ImagePreviewScreen(
            originalFile: originalFile,
            processedFile: processedFile,
          ),
        ),
      );

      // 4️⃣ Update gallery thumbnail
      if (result != null) {
        ref.read(lastImageProvider.notifier).state = result;
      }
    }
  }

  /// 🔦 Flash ON / OFF
  Future<void> toggleFlash() async {
    final controller = state.controller;
    if (controller == null) return;

    final newFlashState = !state.flashOn;

    await controller.setFlashMode(
      newFlashState ? FlashMode.torch : FlashMode.off,
    );

    state = state.copyWith(flashOn: newFlashState);
  }
  Future<void> switchLens(CameraLensType type) async {
    if (type == state.currentLens) return;

    final repo = ref.read(cameraRepositoryProvider);

    state.controller?.dispose();
    state = state.copyWith(isReady: false);

    await repo.initialize(type);

    state = state.copyWith(
      isReady: true,
      controller: repo.controller,
      currentLens: type,
    );
  }

}
