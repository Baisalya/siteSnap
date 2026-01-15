import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/datetime_utils.dart';
import '../../location/presentation/location_viewmodel.dart';
import '../../overlay/domain/overlay_model.dart';
import '../../overlay/presentation/live_overlay_painter.dart';
import '../../overlay/presentation/note_controller.dart';
import '../../overlay/presentation/overlay_preview_state.dart';
import '../presentation/camera_viewmodel.dart';
import 'note_input_sheet.dart';

class CameraScreen extends ConsumerWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Camera state & actions
    final cameraState = ref.watch(cameraViewModelProvider);
    final cameraVM = ref.read(cameraViewModelProvider.notifier);

    // Live overlay data
    final overlayData = ref.watch(overlayPreviewProvider);

    // 🔴 Listen to live location updates and update overlay
    ref.listen(locationStreamProvider, (previous, next) {
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

    // Loading state
    if (!cameraState.isReady || cameraState.controller == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // 🔹 CAMERA PREVIEW AREA
          Expanded(
            child: Stack(
              children: [
                CameraPreview(cameraState.controller!),

                // Live overlay
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: LiveOverlayPainter(overlayData),
                    ),
                  ),
                ),

                // Edit note button (top-right)
                Positioned(
                  top: 48,
                  right: 16,
                  child: IconButton(
                    icon: const Icon(Icons.edit, color: Colors.white),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const NoteInputSheet(),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // 🔹 PROFESSIONAL CAMERA BOTTOM BAR
          Container(
            height: 120,
            width: double.infinity,
            color: Colors.black,
            child: Center(
              child: GestureDetector(
                onTap: () => cameraVM.capture(context),
                child: Container(
                  height: 72,
                  width: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(
                      color: Colors.grey.shade300,
                      width: 4,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
