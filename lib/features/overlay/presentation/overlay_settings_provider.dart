import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';

class OverlaySettingsNotifier extends StateNotifier<OverlaySettings> {
  OverlaySettingsNotifier() : super(const OverlaySettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    final colorValue = prefs.getInt('overlay_bg_color') ?? Colors.white.value;
    final textColorValue = prefs.getInt('overlay_text_color') ?? Colors.black.value;
    final opacity = prefs.getDouble('overlay_bg_opacity') ?? 0.85;
    final showDateTime = prefs.getBool('overlay_show_datetime') ?? true;
    final showCoordinates = prefs.getBool('overlay_show_coordinates') ?? true;
    final showAltitude = prefs.getBool('overlay_show_altitude') ?? true;
    final showDirection = prefs.getBool('overlay_show_direction') ?? true;
    final showNote = prefs.getBool('overlay_show_note') ?? true;
    final showWeather = prefs.getBool('overlay_show_weather') ?? false;
    final showHumidity = prefs.getBool('overlay_show_humidity') ?? false;
    final showAir = prefs.getBool('overlay_show_air') ?? false;
    final showPressure = prefs.getBool('overlay_show_pressure') ?? false;

    final coordinateFormatIndex = prefs.getInt('overlay_coordinate_format') ?? 0;
    final languageIndex = prefs.getInt('overlay_language') ?? 0;
    final use24HourTime = prefs.getBool('overlay_24hour') ?? true;

    state = OverlaySettings(
      backgroundColor: Color(colorValue),
      textColor: Color(textColorValue),
      backgroundOpacity: opacity,
      showDateTime: showDateTime,
      showCoordinates: showCoordinates,
      showAltitude: showAltitude,
      showDirection: showDirection,
      showNote: showNote,
      showWeather: showWeather,
      showHumidity: showHumidity,
      showAir: showAir,
      showPressure: showPressure,
      coordinateFormat: CoordinateFormat.values[coordinateFormatIndex.clamp(0, CoordinateFormat.values.length - 1)],
      language: AppLanguage.values[languageIndex.clamp(0, AppLanguage.values.length - 1)],
      use24HourTime: use24HourTime,
    );
  }

  Future<void> updateSettings(OverlaySettings settings) async {
    state = settings;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('overlay_bg_color', settings.backgroundColor.value);
    await prefs.setInt('overlay_text_color', settings.textColor.value);
    await prefs.setDouble('overlay_bg_opacity', settings.backgroundOpacity);
    await prefs.setBool('overlay_show_datetime', settings.showDateTime);
    await prefs.setBool('overlay_show_coordinates', settings.showCoordinates);
    await prefs.setBool('overlay_show_altitude', settings.showAltitude);
    await prefs.setBool('overlay_show_direction', settings.showDirection);
    await prefs.setBool('overlay_show_note', settings.showNote);
    await prefs.setBool('overlay_show_weather', settings.showWeather);
    await prefs.setBool('overlay_show_humidity', settings.showHumidity);
    await prefs.setBool('overlay_show_air', settings.showAir);
    await prefs.setBool('overlay_show_pressure', settings.showPressure);
    await prefs.setInt('overlay_coordinate_format', settings.coordinateFormat.index);
    await prefs.setInt('overlay_language', settings.language.index);
    await prefs.setBool('overlay_24hour', settings.use24HourTime);
  }

  void setBackgroundColor(Color color) => updateSettings(state.copyWith(backgroundColor: color));
  void setTextColor(Color color) => updateSettings(state.copyWith(textColor: color));
  void setBackgroundOpacity(double opacity) => updateSettings(state.copyWith(backgroundOpacity: opacity));
  void setShowDateTime(bool value) => updateSettings(state.copyWith(showDateTime: value));
  void setShowCoordinates(bool value) => updateSettings(state.copyWith(showCoordinates: value));
  void setShowAltitude(bool value) => updateSettings(state.copyWith(showAltitude: value));
  void setShowDirection(bool value) => updateSettings(state.copyWith(showDirection: value));
  void setShowNote(bool value) => updateSettings(state.copyWith(showNote: value));
  void setShowWeather(bool value) => updateSettings(state.copyWith(showWeather: value));
  void setShowHumidity(bool value) => updateSettings(state.copyWith(showHumidity: value));
  void setShowAir(bool value) => updateSettings(state.copyWith(showAir: value));
  void setShowPressure(bool value) => updateSettings(state.copyWith(showPressure: value));
  void setCoordinateFormat(CoordinateFormat format) => updateSettings(state.copyWith(coordinateFormat: format));
  void setLanguage(AppLanguage lang) => updateSettings(state.copyWith(language: lang));
  void setUse24HourTime(bool value) => updateSettings(state.copyWith(use24HourTime: value));

  Future<void> resetToDefaults() async {
    await updateSettings(const OverlaySettings());
  }
}

final overlaySettingsProvider =
    StateNotifierProvider<OverlaySettingsNotifier, OverlaySettings>((ref) {
  return OverlaySettingsNotifier();
});
