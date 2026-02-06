import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/permissions/permission_service.dart';
import '../../gallery/presentation/image_preview_screen.dart';
import '../../gallery/presentation/last_image_provider.dart';
import '../../overlay/presentation/overlay_viewmodel.dart';
import '../domain/camera_lens_type.dart';

final cameraViewModelProvider =
StateNotifierProvider<CameraViewModel, CameraState>((ref) {
  return CameraViewModel(ref);
});

/// =======================================================
/// ✅ CAMERA STATE
/// =======================================================
class CameraState {
  final bool isReady;
  final CameraController? controller;
  final bool flashOn;
  final CameraLensType currentLens;
  final bool isCapturing;

  const CameraState({
    required this.isReady,
    this.controller,
    this.flashOn = false,
    this.currentLens = CameraLensType.normal,
    this.isCapturing = false,
  });

  CameraState copyWith({
    bool? isReady,
    CameraController? controller,
    bool? flashOn,
    CameraLensType? currentLens,
    bool? isCapturing,
  }) {
    return CameraState(
      isReady: isReady ?? this.isReady,
      controller: controller ?? this.controller,
      flashOn: flashOn ?? this.flashOn,
      currentLens: currentLens ?? this.currentLens,
      isCapturing: isCapturing ?? this.isCapturing,
    );
  }
}

/// =======================================================
/// ✅ CAMERA VIEWMODEL (PRO STABLE VERSION)
/// =======================================================
class CameraViewModel extends StateNotifier<CameraState>
    with WidgetsBindingObserver {
  final Ref ref;

  CameraViewModel(this.ref)
      : super(const CameraState(isReady: false)) {
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  /// =======================================================
  /// ✅ INITIALIZE CAMERA + PERMISSIONS
  /// =======================================================
  Future<void> _init() async {
    try {
      await PermissionService.requestCameraAndLocation();

      final repo = ref.read(cameraRepositoryProvider);
      await repo.initialize(CameraLensType.normal);

      state = state.copyWith(
        isReady: true,
        controller: repo.controller,
        currentLens: CameraLensType.normal,
      );
    } catch (e) {
      debugPrint('Init error: $e');
    }
  }

  /// =======================================================
  /// ✅ APP LIFECYCLE HANDLING (VERY IMPORTANT)
  /// =======================================================
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    final controller = state.controller;

    if (controller == null) return;

    if (lifecycleState == AppLifecycleState.inactive ||
        lifecycleState == AppLifecycleState.paused) {
      controller.dispose();
      state = state.copyWith(isReady: false);
    }

    if (lifecycleState == AppLifecycleState.resumed) {
      _reinitializeCamera();
    }
  }

  Future<void> _reinitializeCamera() async {
    try {
      final repo = ref.read(cameraRepositoryProvider);

      await repo.initialize(state.currentLens);

      state = state.copyWith(
        controller: repo.controller,
        isReady: true,
      );
    } catch (e) {
      debugPrint('Camera reinit failed: $e');
    }
  }

  /// =======================================================
  /// 📸 CAPTURE IMAGE (SAFE VERSION)
  /// =======================================================
  Future<void> capture(BuildContext context) async {
    final controller = state.controller;

    if (!state.isReady ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        state.isCapturing) {
      return;
    }

    state = state.copyWith(isCapturing: true);

    try {
      final repo = ref.read(cameraRepositoryProvider);

      final originalPath = await repo.takePicture();
      final originalFile = File(originalPath);

      final processedFile = await ref
          .read(overlayViewModelProvider.notifier)
          .processImage(originalFile);

      if (!context.mounted) return;

      final result = await Navigator.push<File>(
        context,
        MaterialPageRoute(
          builder: (_) => ImagePreviewScreen(
            originalFile: originalFile,
            processedFile: processedFile,
          ),
        ),
      );

      if (result != null) {
        ref.read(lastImageProvider.notifier).state = result;
      }
    } catch (e) {
      debugPrint('Capture error: $e');
    } finally {
      state = state.copyWith(isCapturing: false);
    }
  }

  /// =======================================================
  /// 🔦 FLASH TOGGLE
  /// =======================================================
  Future<void> toggleFlash() async {
    final controller = state.controller;
    if (controller == null) return;

    final newFlashState = !state.flashOn;

    await controller.setFlashMode(
      newFlashState ? FlashMode.torch : FlashMode.off,
    );

    state = state.copyWith(flashOn: newFlashState);
  }

  /// =======================================================
  /// 🔍 SWITCH LENS
  /// =======================================================
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

  /// =======================================================
  /// 🎯 TAP TO FOCUS + EXPOSURE
  /// =======================================================
  Future<void> setFocusPoint(
      Offset position, Size previewSize) async {
    final controller = state.controller;
    if (controller == null) return;

    try {
      final dx = position.dx / previewSize.width;
      final dy = position.dy / previewSize.height;

      await controller.setFocusPoint(Offset(dx, dy));
      await controller.setExposurePoint(Offset(dx, dy));

      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
    } catch (_) {}
  }

  /// =======================================================
  /// CLEANUP
  /// =======================================================
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    state.controller?.dispose();
    super.dispose();
  }
}
