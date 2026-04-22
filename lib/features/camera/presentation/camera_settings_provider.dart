import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CameraSettings {
  final bool autoFetchLocation;

  CameraSettings({this.autoFetchLocation = true});

  CameraSettings copyWith({bool? autoFetchLocation}) {
    return CameraSettings(
      autoFetchLocation: autoFetchLocation ?? this.autoFetchLocation,
    );
  }
}

class CameraSettingsNotifier extends StateNotifier<CameraSettings> {
  CameraSettingsNotifier() : super(CameraSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final autoFetch = prefs.getBool('auto_fetch_location') ?? true;
    state = state.copyWith(autoFetchLocation: autoFetch);
  }

  Future<void> setAutoFetchLocation(bool value) async {
    state = state.copyWith(autoFetchLocation: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_fetch_location', value);
  }
}

final cameraSettingsProvider =
    StateNotifierProvider<CameraSettingsNotifier, CameraSettings>((ref) {
  return CameraSettingsNotifier();
});
