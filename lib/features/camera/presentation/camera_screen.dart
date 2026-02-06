import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/datetime_utils.dart';
import '../../../core/utils/direction_utils.dart';
import '../../compass/presentation/compass_provider.dart';
import '../../gallery/presentation/gallery_image_viewer.dart';
import '../../gallery/presentation/last_image_provider.dart';
import '../../location/presentation/location_viewmodel.dart';
import '../../overlay/presentation/live_overlay_painter.dart';
import '../../overlay/presentation/overlay_preview_state.dart';
import 'camera_viewmodel.dart';
import 'note_input_sheet.dart';

class CameraScreen extends ConsumerWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameraState = ref.watch(cameraViewModelProvider);
    final cameraVM = ref.read(cameraViewModelProvider.notifier);

    final overlayData = ref.watch(overlayPreviewProvider);
    final lastImage = ref.watch(lastImageProvider);

    // 📍 LOCATION → overlay
    ref.listen(locationStreamProvider, (_, next) {
      next.whenData((position) {
        final current = ref.read(overlayPreviewProvider);
        ref.read(overlayPreviewProvider.notifier).state =
            current.copyWith(
              dateTime: DateTimeUtils.formattedNow(),
              latitude: position.latitude,   // ✅ FIX
              longitude: position.longitude, // ✅ FIX
              altitude: position.altitude,
            );
      });
    });

    // 🧭 COMPASS → overlay
    ref.listen(compassHeadingProvider, (_, next) {
      next.whenData((heading) {
        final current = ref.read(overlayPreviewProvider);
        ref.read(overlayPreviewProvider.notifier).state =
            current.copyWith(
              heading: heading,
              direction: DirectionUtils.toCardinal(heading),
            );
      });
    });

    if (!cameraState.isReady || cameraState.controller == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // ================= CAMERA PREVIEW =================
          Expanded(
            child: Stack(
              children: [
                CameraPreview(cameraState.controller!),

                // 🔴 LIVE OVERLAY
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: LiveOverlayPainter(overlayData),
                    ),
                  ),
                ),

                // ✏️ Edit note
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

          // ================= BOTTOM BAR =================
          Container(
            height: 140,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            color: Colors.black,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Flash
                IconButton(
                  icon: Icon(
                    cameraState.flashOn
                        ? Icons.flash_on
                        : Icons.flash_off,
                    color: Colors.white,
                  ),
                  onPressed: cameraVM.toggleFlash,
                ),

                // Capture
                GestureDetector(
                  onTap: () => cameraVM.capture(context),
                  child: Container(
                    height: 72,
                    width: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                        color: Colors.grey.shade400,
                        width: 4,
                      ),
                    ),
                  ),
                ),

                // Gallery
                GestureDetector(
                  onTap: lastImage != null
                      ? () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            GalleryImageViewer(file: lastImage),
                      ),
                    );
                  }
                      : null,
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.grey.shade800,
                    backgroundImage:
                    lastImage != null ? FileImage(lastImage) : null,
                    child: lastImage == null
                        ? const Icon(Icons.image, color: Colors.white)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
