import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/utils/device_orientation_provider.dart';
import '../../gallery/presentation/image_preview_screen.dart';
import '../../gallery/presentation/last_image_provider.dart';
import '../../location/presentation/location_viewmodel.dart';
import '../../overlay/presentation/overlay_viewmodel.dart';
import '../data/CameraState.dart';
import '../domain/camera_lens_type.dart';

final cameraViewModelProvider =
StateNotifierProvider<CameraViewModel, CameraState>((ref) {
  return CameraViewModel(ref);
});

class CameraViewModel extends StateNotifier<CameraState>
    with WidgetsBindingObserver {
  final Ref ref;

  CameraViewModel(this.ref)
      : super(const CameraState(isReady: false)) {
    WidgetsBinding.instance.addObserver(this);
    _init();
  }
  /// =======================================================
  /// INIT CAMERA
  /// =======================================================
  Future<void> _init() async {
    try {
      await PermissionService.requestCameraAndLocation();
      ref.invalidate(locationStreamProvider);

      final repo = ref.read(cameraRepositoryProvider);
      await repo.initialize(CameraLensType.normal);

      final controller = repo.controller;

      if (controller != null) {
        final min = await controller.getMinExposureOffset();
        final max = await controller.getMaxExposureOffset();

        final exposure = (min + max) / 6;
        await controller.setExposureOffset(exposure);
      }

      state = state.copyWith(
        isReady: true,
        controller: controller,
        currentLens: CameraLensType.normal,
      );
    } catch (e) {
      debugPrint('Init error: $e');
    }
  }
  /// =======================================================
  /// UPDATE ORIENTATION FROM SENSOR
  /// (Called from CameraScreen reader)
  /// =======================================================
  void updateOrientation(DeviceOrientation orientation) {
    if (state.orientation != orientation) {
      state = state.copyWith(orientation: orientation);
    }
  }
  /// =======================================================
  /// APP LIFECYCLE
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

  Future<void> _prepareAutoFocus(CameraController controller) async {
    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);

      await Future.delayed(const Duration(milliseconds: 300));

      await controller.setExposureMode(ExposureMode.locked);
    } catch (_) {}
  }
  /// =======================================================
  /// CAPTURE IMAGE (FINAL STABLE VERSION)
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

    final deviceOrientation =
    ref.read(deviceOrientationProvider);

    state = state.copyWith(
      isCapturing: true,
      captureOrientation: deviceOrientation,
    );

    try {
      final repo = ref.read(cameraRepositoryProvider);

      await _prepareAutoFocus(controller);

      final originalPath = await repo.takePicture();
      final originalFile = File(originalPath);

      final processedFile = await ref
          .read(overlayViewModelProvider.notifier)
          .processImage(
        originalFile,
        state.captureOrientation!,
      );

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
  /// FLASH
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
  /// TAP TO FOCUS
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
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    state.controller?.dispose();
    super.dispose();
  }
}
