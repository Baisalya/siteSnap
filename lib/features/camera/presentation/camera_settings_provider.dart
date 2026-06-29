import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surveycam/features/overlay/presentation/overlay_preview_state.dart';

class CameraSettings {
  final bool autoFetchLocation;
  final bool mirrorFrontVideo;

  CameraSettings({
    this.autoFetchLocation = true,
    this.mirrorFrontVideo = false,
  });

  CameraSettings copyWith({
    bool? autoFetchLocation,
    bool? mirrorFrontVideo,
  }) {
    return CameraSettings(
      autoFetchLocation: autoFetchLocation ?? this.autoFetchLocation,
      mirrorFrontVideo: mirrorFrontVideo ?? this.mirrorFrontVideo,
    );
  }
}

class CameraSettingsNotifier extends StateNotifier<CameraSettings> {
  final Ref ref;
  CameraSettingsNotifier(this.ref) : super(CameraSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final autoFetch = prefs.getBool('auto_fetch_location') ?? true;
    final mirrorFrontVideo = prefs.getBool('mirror_front_video') ?? false;
    state = state.copyWith(
      autoFetchLocation: autoFetch,
      mirrorFrontVideo: mirrorFrontVideo,
    );
  }

  Future<void> setAutoFetchLocation(bool value) async {
    state = state.copyWith(autoFetchLocation: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_fetch_location', value);

    if (!value) {
      // Clear location line from watermark
      final overlay = ref.read(overlayPreviewProvider);
      final currentNote = overlay.note;

      // Extract only the extra note (Line 2)
      final lines = currentNote.split(RegExp(r'\r?\n'));
      final extraNote =
          lines.length <= 1 ? '' : lines.skip(1).join('\n').trim();

      // Set note to just the extra note (preserving the separate line status)
      ref.read(overlayPreviewProvider.notifier).state = overlay.copyWith(
          note: extraNote.isEmpty ? '' : "\n$extraNote");
    }
  }

  Future<void> setMirrorFrontVideo(bool value) async {
    state = state.copyWith(mirrorFrontVideo: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mirror_front_video', value);
  }
}

final cameraSettingsProvider =
    StateNotifierProvider<CameraSettingsNotifier, CameraSettings>((ref) {
  return CameraSettingsNotifier(ref);
});
