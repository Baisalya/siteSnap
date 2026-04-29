import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:surveycam/core/di/providers.dart';
import 'package:surveycam/core/permissions/permission_service.dart';
import 'package:surveycam/core/utils/device_orientation_provider.dart';


import 'package:surveycam/features/camera/data/CameraState.dart';
import 'package:surveycam/features/camera/domain/camera_lens_type.dart';
import 'package:surveycam/features/gallery/presentation/image_preview_screen.dart';
import 'package:surveycam/features/gallery/presentation/last_image_provider.dart';
import 'package:surveycam/features/location/presentation/location_viewmodel.dart';
import 'package:surveycam/features/overlay/presentation/captured_overlay_provider.dart';
import 'package:surveycam/features/overlay/presentation/overlay_preview_state.dart';

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
    initialize();
  }

  // ================= INIT =================

  Future<void> initialize() async {
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      await PermissionService.requestCameraAndLocation();
      ref.invalidate(locationStreamProvider);

      final repo = ref.read(cameraRepositoryProvider);
      await repo.initialize(CameraLensType.normal);

      final controller = repo.controller;
      if (controller == null) {
        state = state.copyWith(isReady: false, error: "Controller is null");
        return;
      }

      // Ensure the controller is initialized before proceeding
      if (!controller.value.isInitialized) {
        await controller.initialize();
      }

      // Set to auto focus and exposure by default
      try {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setExposureMode(ExposureMode.auto);
        await controller.setFlashMode(FlashMode.off);
      } catch (e) {
        debugPrint("Initial focus/exposure error: $e");
      }

      // Explicitly set central points to force AE/AF calculation
      await controller.setFocusPoint(const Offset(0.5, 0.5));
      await controller.setExposurePoint(const Offset(0.5, 0.5));

      await Future.delayed(const Duration(milliseconds: 600));

      _minExposure = await controller.getMinExposureOffset();
      _maxExposure = await controller.getMaxExposureOffset();

      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();

      // Start with a slight exposure boost (+0.5) to make dark areas "pop" more
      _currentExposure = 0.5.clamp(_minExposure, _maxExposure);

      await controller.setExposureOffset(_currentExposure);

      _isCameraStable = true;

      state = state.copyWith(
        isReady: true,
        controller: controller,
        exposure: _currentExposure,
        minExposure: _minExposure,
        maxExposure: _maxExposure,
        zoom: 1.0,
        minZoom: minZoom,
        maxZoom: maxZoom,
        error: null,
      );

    } catch (e) {
      debugPrint('Init error: $e');
      state = state.copyWith(isReady: false, error: e.toString());
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
  void didChangeAppLifecycleState(AppLifecycleState appLifecycleState) async {
    if (_isInitializing) return;

    if (appLifecycleState == AppLifecycleState.inactive ||
        appLifecycleState == AppLifecycleState.paused) {
      try {
        // 🔥 Kill flash/torch immediately when app goes to background
        final controller = state.controller;
        if (controller != null && controller.value.isInitialized) {
          if (state.flashMode == FlashMode.always) {
            await _nuclearFlashKill(controller);
          } else {
            await _softFlashQuench(controller);
          }
          await controller.pausePreview();
        }
      } catch (_) {}
    }

    if (appLifecycleState == AppLifecycleState.resumed) {
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
      if (oldController != null && oldController.value.isInitialized) {
        await oldController.dispose();
      }

      final repo = ref.read(cameraRepositoryProvider);
      await repo.initialize(state.currentLens);

      final controller = repo.controller;

      if (controller != null) {
        if (!controller.value.isInitialized) {
          await controller.initialize();
        }
        await controller.setFocusMode(FocusMode.auto);
        await controller.setExposureMode(ExposureMode.auto);
        
        // Explicitly set central points to force AE/AF calculation
        await controller.setFocusPoint(const Offset(0.5, 0.5));
        await controller.setExposurePoint(const Offset(0.5, 0.5));

        // Always start with flash OFF on the controller
        await controller.setFlashMode(FlashMode.off);

        await Future.delayed(const Duration(milliseconds: 400));

        await controller.setExposureOffset(_currentExposure);
      }

      state = state.copyWith(controller: controller, isReady: true, error: null);

    } catch (e) {
      debugPrint("Restart error: $e");
      state = state.copyWith(isReady: false, error: e.toString());
    }
  }
  // ================= FOCUS =================

  Future<void> setFocusPoint(
      Offset position, Size previewSize) async {
    final controller = state.controller;
    if (controller == null) return;

    try {
      final dx = (position.dx / previewSize.width).clamp(0.0, 1.0);
      final dy = (position.dy / previewSize.height).clamp(0.0, 1.0);

      state = state.copyWith(isManualFocus: true);

      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);

      await controller.setFocusPoint(Offset(dx, dy));
      await controller.setExposurePoint(Offset(dx, dy));
    } catch (_) {}
  }

  Future<void> resetFocus() async {
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      state = state.copyWith(isManualFocus: false);

      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
      
      // Reset points to center
      await controller.setFocusPoint(null);
      await controller.setExposurePoint(null);
    } catch (e) {
      debugPrint("Reset focus error: $e");
    }
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

  // ================= ZOOM =================

  Future<void> setZoom(double zoom) async {
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      final clampedZoom = zoom.clamp(state.minZoom, state.maxZoom);
      await controller.setZoomLevel(clampedZoom);
      state = state.copyWith(zoom: clampedZoom);
    } catch (e) {
      debugPrint("Zoom error: $e");
    }
  }

  /// 🔥 THE NUCLEAR FLASH KILL
  /// Specifically designed for Android devices where the LED driver "latches"
  /// on in dark environments when using Auto Flash.
  /// A softer quench that doesn't flicker
  Future<void> _softFlashQuench(CameraController controller) async {
    try {
      if (!controller.value.isInitialized) return;
      await controller.setFlashMode(FlashMode.off);
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (_) {}
  }

  /// The heavy-duty reset for stuck drivers (causes a brief flicker)
  Future<void> _nuclearFlashKill(CameraController controller) async {
    try {
      if (!controller.value.isInitialized) return;

      await controller.setFlashMode(FlashMode.off);
      await Future.delayed(const Duration(milliseconds: 100));

      // Torch "kick" to reset the hardware driver
      await controller.setFlashMode(FlashMode.torch);
      await Future.delayed(const Duration(milliseconds: 150));
      await controller.setFlashMode(FlashMode.off);
      
      // Cooldown to let sensor recover from the burst
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (e) {
      debugPrint("Nuclear flash kill error: $e");
    }
  }

  // ================= FLASH =================

  Future<void> setFlashMode(FlashMode mode) async {
    state = state.copyWith(flashMode: mode);
    
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      if (mode == FlashMode.off) {
        // Just set to off, no nuclear kill needed here as it causes a flicker
        await controller.setFlashMode(FlashMode.off);
      } else {
        // When user selects ON, we keep the controller's flash OFF for now
        // and only enable it during the actual capture to prevent "sticking"
        await controller.setFlashMode(FlashMode.off);
      }
    } catch (e) {
      debugPrint("Error setting flash mode: $e");
    }
  }

  Future<void> cycleFlashMode() async {
    final nextMode = state.flashMode == FlashMode.off ? FlashMode.always : FlashMode.off;
    await setFlashMode(nextMode);
  }

  void setAspectRatio(CameraAspectRatio ratio) {
    state = state.copyWith(aspectRatio: ratio);
  }

  // ================= CAMERA SWITCH =================

  Future<void> switchCamera() async {
    if (_isInitializing || _isRestarting) return;

    final nextLens = state.currentLens == CameraLensType.front
        ? CameraLensType.normal
        : CameraLensType.front;

    state = state.copyWith(currentLens: nextLens, isReady: false);

    try {
      final repo = ref.read(cameraRepositoryProvider);
      await repo.initialize(nextLens);

      final controller = repo.controller;
      if (controller != null) {
        if (!controller.value.isInitialized) {
          await controller.initialize();
        }

        _minExposure = await controller.getMinExposureOffset();
        _maxExposure = await controller.getMaxExposureOffset();
        final minZoom = await controller.getMinZoomLevel();
        final maxZoom = await controller.getMaxZoomLevel();

        state = state.copyWith(
          isReady: true,
          controller: controller,
          exposure: 0.0,
          minExposure: _minExposure,
          maxExposure: _maxExposure,
          zoom: 1.0,
          minZoom: minZoom,
          maxZoom: maxZoom,
          error: null,
        );
      }
    } catch (e) {
      debugPrint("Switch camera error: $e");
      state = state.copyWith(isReady: false, error: e.toString());
    }
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
    
    unawaited(HapticFeedback.mediumImpact());

    final overlayData = ref.read(overlayPreviewProvider);
    ref.read(capturedOverlayProvider.notifier).state = overlayData;
    final deviceOrientation = ref.read(deviceOrientationProvider);

    state = state.copyWith(
      isCapturing: true,
      captureOrientation: deviceOrientation,
      captureLens: state.currentLens,
    );

    try {
      final repo = ref.read(cameraRepositoryProvider);

      // 1. Prepare hardware
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
      // Re-trigger metering on the center point to maximize gain
      await controller.setExposurePoint(const Offset(0.5, 0.5));

      // 2. Enable Light for Capture
      if (state.flashMode == FlashMode.always) {
        if (state.currentLens == CameraLensType.front) {
          // For front camera, we use the Screen Flash (UI based)
          // We wait a moment for the screen to turn bright white in the UI
          await Future.delayed(const Duration(milliseconds: 300));
        } else {
          // For back camera, use the physical LED
          await controller.setFlashMode(FlashMode.torch);
          await Future.delayed(const Duration(milliseconds: 800));
        }
        // LOCK exposure while it's bright so it doesn't dim during capture
        await controller.setExposureMode(ExposureMode.locked);
      } else {
        await controller.setFlashMode(FlashMode.off);
        // Wait longer (500ms) for AE to reach its peak gain in dark areas
        await Future.delayed(const Duration(milliseconds: 500));
        // Lock exposure so it doesn't drop during the shutter process
        await controller.setExposureMode(ExposureMode.locked);
      }

      // 3. CAPTURE
      final path = await repo.takePicture();

      // 4. IMMEDIATE CLEANUP
      // Give the hardware a tiny breath to finalize the file write
      await Future.delayed(const Duration(milliseconds: 200));

      if (state.flashMode == FlashMode.always) {
        await _nuclearFlashKill(controller);
      } else {
        await _softFlashQuench(controller);
      }

      unawaited(HapticFeedback.lightImpact());
      await _handlePostCapture(path, context, deviceOrientation);

    } catch (e) {
      debugPrint('Capture error: $e');
    } finally {
      // 🔓 RESTORATION
      try {
        if (controller.value.isInitialized) {
          // IMPORTANT: Keep controller flash OFF during preview to prevent sticking.
          await controller.setFlashMode(FlashMode.off);
          
          await controller.setFocusMode(FocusMode.auto);
          await controller.setExposureMode(ExposureMode.auto);
          await controller.setExposureOffset(_currentExposure);

          // Kick the pipeline to ensure it's not hung
          await controller.resumePreview();
          
          // Extra stabilization delay before allowing the next capture
          await Future.delayed(const Duration(milliseconds: 400));
        }
      } catch (e) {
        debugPrint("Restoration error: $e");
      }
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
      if (!context.mounted) return;

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImagePreviewScreen(
            originalFile: originalFile,
            processedFile: originalFile,
          ),
        ),
      );

      if (result != null) {
        ref.read(lastImageProvider.notifier).state = originalFile;
      }
    } catch (e) {
      debugPrint("Post capture error: $e");
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
