import 'dart:async';
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
import '../../overlay/presentation/captured_overlay_provider.dart';
import '../../overlay/presentation/overlay_preview_state.dart';
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

  bool _isCameraStable = false;
  bool _isInitializing = false;
  bool _isRestarting = false;

  bool get isCameraStable => _isCameraStable;
  double get exposureValue => _currentExposure;

  CameraViewModel(this.ref)
      : super(const CameraState(isReady: false)) {
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  // ================= INIT =================

  Future<void> _init() async {
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      await PermissionService.requestCameraAndLocation();
      ref.invalidate(locationStreamProvider);

      final repo = ref.read(cameraRepositoryProvider);
      await repo.initialize(CameraLensType.normal);

      final controller = repo.controller;
      if (controller == null) return;

      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);

      await controller.setFocusPoint(const Offset(0.5, 0.5));
      await controller.setExposurePoint(const Offset(0.5, 0.5));

      await Future.delayed(const Duration(milliseconds: 600));

      _minExposure = await controller.getMinExposureOffset();
      _maxExposure = await controller.getMaxExposureOffset();

      _currentExposure =
          ((_minExposure + _maxExposure) / 2)
              .clamp(_minExposure, _maxExposure);

      await controller.setExposureOffset(_currentExposure);

      _isCameraStable = true;

      state = state.copyWith(
        isReady: true,
        controller: controller,
        exposure: _currentExposure,
      );

    } catch (e) {
      debugPrint('Init error: $e');
    } finally {
      _isInitializing = false;
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
    if (_isInitializing) return;

    if (lifecycleState == AppLifecycleState.inactive ||
        lifecycleState == AppLifecycleState.paused) {
      try {
        await state.controller?.pausePreview();
      } catch (_) {}
    }

    if (lifecycleState == AppLifecycleState.resumed) {
      if (_isRestarting) return;

      _isRestarting = true;
      try {
        await _restartCamera();
      } finally {
        _isRestarting = false;
      }
    }
  }

  // ================= RESTART =================

  Future<void> _restartCamera() async {
    try {
      final oldController = state.controller;

      state = state.copyWith(controller: null, isReady: false);

      await Future.delayed(const Duration(milliseconds: 50));
      await oldController?.dispose();

      final repo = ref.read(cameraRepositoryProvider);
      await repo.initialize(state.currentLens);

      final controller = repo.controller;

      if (controller != null) {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setExposureMode(ExposureMode.auto);

        await Future.delayed(const Duration(milliseconds: 400));

        await controller.setExposureOffset(_currentExposure);
      }

      state = state.copyWith(controller: controller, isReady: true);

    } catch (e) {
      debugPrint("Restart error: $e");
    }
  }
  // ================= AUTO FOCUS =================
  Future<void> _prepareAutoFocus(CameraController controller) async {
    try {
      if (!controller.value.isInitialized) return;

      /// reset focus + exposure for accurate metering
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);

      /// give sensor time to settle
      await Future.delayed(const Duration(milliseconds: 250));

    } catch (e) {
      debugPrint("AutoFocus error: $e");
    }
  }
  // ================= FOCUS =================

  Future<void> setFocusPoint(
      Offset position, Size previewSize) async {
    final controller = state.controller;
    if (controller == null) return;

    try {
      final dx = position.dx / previewSize.width;
      final dy = position.dy / previewSize.height;

      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);

      await controller.setFocusPoint(Offset(dx, dy));
      await controller.setExposurePoint(Offset(dx, dy));
    } catch (_) {}
  }

  // ================= EXPOSURE =================

  Future<void> changeExposure(double delta) async {
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      _currentExposure =
          (_currentExposure + delta)
              .clamp(_minExposure, _maxExposure);

      await controller.setExposureOffset(_currentExposure);

      state = state.copyWith(exposure: _currentExposure);

    } catch (e) {
      debugPrint("Exposure error: $e");
    }
  }
  Future<void> _adjustExposureForCapture(CameraController controller) async {
    try {
      double adjustedExposure = _currentExposure;

      /// 🔥 If flash ON → reduce exposure
      if (state.flashOn) {
        adjustedExposure -= 0.5; // tweak value if needed
      }

      /// 🌙 If scene is dark (user already increased exposure)
      if (_currentExposure < (_minExposure + _maxExposure) / 4) {
        adjustedExposure += 0.3;
      }

      adjustedExposure =
          adjustedExposure.clamp(_minExposure, _maxExposure);

      await controller.setExposureOffset(adjustedExposure);

    } catch (e) {
      debugPrint("Smart exposure error: $e");
    }
  }
  // ================= FLASH =================

  Future<void> toggleFlash() async {
    final controller = state.controller;
    if (controller == null) return;

    final newFlashState = !state.flashOn;

    await controller.setFlashMode(
      newFlashState ? FlashMode.torch : FlashMode.off,
    );

    state = state.copyWith(flashOn: newFlashState);
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
    final overlayData = ref.read(overlayPreviewProvider);

// 🔥 FREEZE SNAPSHOT HERE
    ref.read(capturedOverlayProvider.notifier).state = overlayData;
    final deviceOrientation = ref.read(deviceOrientationProvider);

    state = state.copyWith(
      isCapturing: true,
      captureOrientation: deviceOrientation,
    );

    try {
      final repo = ref.read(cameraRepositoryProvider);

      /// 📸 QUICK PREP (reduced delay)
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);

      /// ⚡ CAPTURE ASAP (no heavy delay)
      final path = await repo.takePicture();

      /// 🔥 restore exposure immediately
      await controller.setExposureMode(ExposureMode.auto);

      /// 🚀 PROCESS IN BACKGROUND
      unawaited(_handlePostCapture(
        path,
        context,
        deviceOrientation,
      ));

    } catch (e) {
      debugPrint('Capture error: $e');
      state = state.copyWith(isCapturing: false);
    }
  }
  Future<void> _handlePostCapture(
      String path,
      BuildContext context,
      DeviceOrientation orientation,
      ) async {
    try {
      final originalFile = File(path);

      /// 📂 create processed copy
      final processedPath =
      path.replaceFirst('.jpg', '_processed.jpg');

      final copiedFile = await originalFile.copy(processedPath);

      /// 🎨 heavy processing (background)
      final captured = ref.read(capturedOverlayProvider);
      final live = ref.read(overlayPreviewProvider);

      final overlayData = (captured ?? live).copyWith(
        note: live.note,
      );

      final processedFile = await ref
          .read(overlayViewModelProvider.notifier)
          .processImage(
        copiedFile,
        orientation,
        overlayData: overlayData, // ✅ FIX
      );

      if (!context.mounted) return;

      /// 🖼 open preview AFTER processing
      final result = await Navigator.push<File>(
        context,
        MaterialPageRoute(
          builder: (_) => ImagePreviewScreen(
            originalFile: originalFile,
            processedFile: processedFile,
          ),
        ),
      );

      /// 💾 update last image
      if (result != null) {
        ref.read(lastImageProvider.notifier).state = result;
      }

    } catch (e) {
      debugPrint("Post capture error: $e");
    } finally {
      /// 🔓 unlock capture state AFTER everything
      state = state.copyWith(isCapturing: false);
    }
  }
  // ================= DISPOSE =================

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    state.controller?.dispose();
    super.dispose();
  }
}