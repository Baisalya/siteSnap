import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../overlay/presentation/live_overlay_painter.dart';
import '../../overlay/presentation/overlay_preview_state.dart';
import '../../location/presentation/location_viewmodel.dart';
import '../presentation/camera_viewmodel.dart';
import '../../../core/utils/datetime_utils.dart';

class CameraScreen extends ConsumerWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraState = ref.watch(cameraViewModelProvider);
    final cameraVM = ref.read(cameraViewModelProvider.notifier);

    // 🔴 Live location updates
    ref.listen(locationStreamProvider, (prev, next) {
      next.whenData((position) {
        final current = ref.read(overlayPreviewProvider);

        ref.read(overlayPreviewProvider.notifier).state =
            current.copyWith(
              dateTime: DateTimeUtils.formattedNow(),
              lat: position.latitude,
              lng: position.longitude,
              altitude: position.altitude,
            );
      });
    });

    if (!cameraState.isReady || cameraState.controller == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final overlayData = ref.watch(overlayPreviewProvider);

    return Scaffold(
      body: Stack(
        children: [
          CameraPreview(cameraState.controller!),

          // ✅ LIVE OVERLAY PREVIEW
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: LiveOverlayPainter(overlayData),
              ),
            ),
          ),

          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: IconButton(
                iconSize: 72,
                icon: const Icon(Icons.camera_alt, color: Colors.white),
                onPressed: () => cameraVM.capture(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
