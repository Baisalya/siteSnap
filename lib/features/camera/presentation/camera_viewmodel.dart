import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../core/utils/datetime_utils.dart';
import '../../gallery/presentation/image_preview_screen.dart';
import '../../overlay/presentation/overlay_viewmodel.dart';

final cameraViewModelProvider =
StateNotifierProvider<CameraViewModel, CameraState>((ref) {
  return CameraViewModel(ref);
});

class CameraState {
  final bool isReady;
  final CameraController? controller;

  CameraState({required this.isReady, this.controller});
}

class CameraViewModel extends StateNotifier<CameraState> {
  final Ref ref;

  CameraViewModel(this.ref) : super(CameraState(isReady: false)) {
    _init();
  }

  Future<void> _init() async {
    final repo = ref.read(cameraRepositoryProvider);
    await repo.initialize();
    state = CameraState(isReady: true, controller: repo.controller);
  }

  CameraController get controller => state.controller!;

  Future<void> capture(BuildContext context) async {
    final repo = ref.read(cameraRepositoryProvider);
    final path = await repo.takePicture();

    final processedFile =
    await ref.read(overlayViewModelProvider.notifier)
        .processImage(File(path), DateTimeUtils.formattedNow());

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImagePreviewScreen(file: processedFile),
        ),
      );
    }
  }
}
