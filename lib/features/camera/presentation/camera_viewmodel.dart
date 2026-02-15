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

  double _currentExposure = 0.0;
  double _minExposure = 0.0;
  double _maxExposure = 0.0;

  CameraViewModel(this.ref)
      : super(const CameraState(isReady: false)) {
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  double get exposureValue => _currentExposure;

  // ================= INIT =================

  Future<void> _init() async {
    try {
      await PermissionService.requestCameraAndLocation();
      ref.invalidate(locationStreamProvider);

      final repo = ref.read(cameraRepositoryProvider);
      await repo.initialize(CameraLensType.normal);

      final controller = repo.controller;

      if (controller != null) {
        await controller.setFocusPoint(const Offset(0.5, 0.5));
        await controller.setExposurePoint(const Offset(0.5, 0.5));

        _minExposure = await controller.getMinExposureOffset();
        _maxExposure = await controller.getMaxExposureOffset();

        _currentExposure =
            ((_minExposure + _maxExposure) / 4)
                .clamp(_minExposure, _maxExposure);

        await controller.setExposureOffset(_currentExposure);
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

  // ================= ORIENTATION =================

  void updateOrientation(DeviceOrientation orientation) {
    if (state.orientation != orientation) {
      state = state.copyWith(orientation: orientation);
    }
  }

  // ================= LIFECYCLE =================

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) async {

    if (lifecycleState == AppLifecycleState.inactive ||
        lifecycleState == AppLifecycleState.paused) {

      try {
        await state.controller?.pausePreview();
      } catch (_) {}
    }

    if (lifecycleState == AppLifecycleState.resumed) {
      await _restartCamera();
    }
  }

  // ================= RESTART CAMERA =================

  Future<void> _restartCamera() async {
    try {
      final oldController = state.controller;

      // remove controller from UI first
      state = state.copyWith(
        controller: null,
        isReady: false,
      );

      // wait one frame so CameraPreview unmounts
      await Future.delayed(const Duration(milliseconds: 50));

      // dispose old controller safely
      try {
        await oldController?.dispose();
      } catch (_) {}

      final repo = ref.read(cameraRepositoryProvider);
      await repo.initialize(state.currentLens);

      final newController = repo.controller;

      state = state.copyWith(
        controller: newController,
        isReady: true,
      );

    } catch (e) {
      debugPrint("Camera restart failed: $e");
    }
  }

  // ================= AUTO FOCUS =================

  Future<void> _prepareAutoFocus(
      CameraController controller) async {
    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);

      await Future.delayed(const Duration(milliseconds: 350));

      await controller.setExposureMode(ExposureMode.locked);
    } catch (_) {}
  }

  // ================= CAPTURE =================

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
      await Future.delayed(const Duration(milliseconds: 120));

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

  // ================= FLASH =================

  Future<void> toggleFlash() async {
    final controller = state.controller;
    if (controller == null) return;

    final newFlashState = !state.flashOn;

    await controller.setFlashMode(
      newFlashState ? FlashMode.auto : FlashMode.off,
    );

    state = state.copyWith(flashOn: newFlashState);
  }

  // ================= FOCUS =================

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

  // ================= EXPOSURE =================

  Future<void> changeExposure(double delta) async {
    final controller = state.controller;
    if (controller == null) return;

    try {
      _currentExposure =
          (_currentExposure + delta)
              .clamp(_minExposure, _maxExposure);

      await controller.setExposureOffset(_currentExposure);

      state = state.copyWith();
    } catch (_) {}
  }

  // ================= DISPOSE =================

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      state.controller?.dispose();
    } catch (_) {}
    super.dispose();
  }
}
