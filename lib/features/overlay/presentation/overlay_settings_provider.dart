import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';

class OverlaySettingsNotifier extends StateNotifier<OverlaySettings> {
  OverlaySettingsNotifier() : super(const OverlaySettings()) {
    _loadSettings();
  }

  Timer? _persistTimer;

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final colorValue = prefs.getInt('overlay_bg_color') ?? Colors.white.value;
    final textColorValue =
        prefs.getInt('overlay_text_color') ?? Colors.black.value;
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
    final watermarkPresetIndex =
        prefs.getInt('overlay_watermark_preset_index') ?? 0;
    final watermarkText = prefs.getString('overlay_watermark_text') ?? '';
    final watermarkLogoPath = prefs.getString('overlay_watermark_logo_path');
    final watermarkShowLogo =
        prefs.getBool('overlay_watermark_show_logo') ?? true;
    final watermarkText2 = prefs.getString('overlay_watermark_text_2') ?? '';
    final watermarkLogoPath2 = prefs.getString('overlay_watermark_logo_path_2');
    final watermarkShowLogo2 =
        prefs.getBool('overlay_watermark_show_logo_2') ?? true;

    final coordinateFormatIndex =
        prefs.getInt('overlay_coordinate_format') ?? 0;
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
      watermarkPresetIndex: watermarkPresetIndex,
      watermarkText: watermarkText,
      watermarkLogoPath: watermarkLogoPath,
      watermarkShowLogo: watermarkShowLogo,
      watermarkText2: watermarkText2,
      watermarkLogoPath2: watermarkLogoPath2,
      watermarkShowLogo2: watermarkShowLogo2,
      coordinateFormat: CoordinateFormat.values[
          coordinateFormatIndex.clamp(0, CoordinateFormat.values.length - 1)],
      language: AppLanguage
          .values[languageIndex.clamp(0, AppLanguage.values.length - 1)],
      use24HourTime: use24HourTime,
    );
  }

  Future<void> updateSettings(
    OverlaySettings settings, {
    bool persistImmediately = false,
  }) async {
    state = settings;
    _persistTimer?.cancel();
    if (persistImmediately) {
      await _persistSettings(settings);
      return;
    }

    _persistTimer = Timer(const Duration(milliseconds: 300), () {
      _persistSettings(state);
    });
  }

  Future<void> _persistSettings(OverlaySettings settings) async {
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
    await prefs.setInt(
        'overlay_watermark_preset_index', settings.watermarkPresetIndex);
    await prefs.setString('overlay_watermark_text', settings.watermarkText);
    if (settings.watermarkLogoPath == null) {
      await prefs.remove('overlay_watermark_logo_path');
    } else {
      await prefs.setString(
          'overlay_watermark_logo_path', settings.watermarkLogoPath!);
    }
    await prefs.setBool(
        'overlay_watermark_show_logo', settings.watermarkShowLogo);
    await prefs.setString('overlay_watermark_text_2', settings.watermarkText2);
    if (settings.watermarkLogoPath2 == null) {
      await prefs.remove('overlay_watermark_logo_path_2');
    } else {
      await prefs.setString(
          'overlay_watermark_logo_path_2', settings.watermarkLogoPath2!);
    }
    await prefs.setBool(
        'overlay_watermark_show_logo_2', settings.watermarkShowLogo2);
    await prefs.setInt(
        'overlay_coordinate_format', settings.coordinateFormat.index);
    await prefs.setInt('overlay_language', settings.language.index);
    await prefs.setBool('overlay_24hour', settings.use24HourTime);
  }

  void setBackgroundColor(Color color) =>
      updateSettings(state.copyWith(backgroundColor: color));
  void setTextColor(Color color) =>
      updateSettings(state.copyWith(textColor: color));
  void setBackgroundOpacity(double opacity) =>
      updateSettings(state.copyWith(backgroundOpacity: opacity));
  void setShowDateTime(bool value) =>
      updateSettings(state.copyWith(showDateTime: value));
  void setShowCoordinates(bool value) =>
      updateSettings(state.copyWith(showCoordinates: value));
  void setShowAltitude(bool value) =>
      updateSettings(state.copyWith(showAltitude: value));
  void setShowDirection(bool value) =>
      updateSettings(state.copyWith(showDirection: value));
  void setShowNote(bool value) =>
      updateSettings(state.copyWith(showNote: value));
  void setShowWeather(bool value) =>
      updateSettings(state.copyWith(showWeather: value));
  void setShowHumidity(bool value) =>
      updateSettings(state.copyWith(showHumidity: value));
  void setShowAir(bool value) => updateSettings(state.copyWith(showAir: value));
  void setShowPressure(bool value) =>
      updateSettings(state.copyWith(showPressure: value));
  void setWatermarkPresetIndex(int value) =>
      updateSettings(state.copyWith(watermarkPresetIndex: value));
  void setWatermarkTextForSlot(int slot, String value) {
    if (slot == 2) {
      updateSettings(state.copyWith(watermarkText2: value));
    } else {
      updateSettings(state.copyWith(watermarkText: value));
    }
  }

  void setWatermarkLogoPathForSlot(int slot, String value) {
    if (slot == 2) {
      updateSettings(
          state.copyWith(watermarkLogoPath2: value, watermarkShowLogo2: true));
    } else {
      updateSettings(
          state.copyWith(watermarkLogoPath: value, watermarkShowLogo: true));
    }
  }

  void clearWatermarkLogoPathForSlot(int slot) {
    if (slot == 2) {
      updateSettings(state.copyWith(clearWatermarkLogoPath2: true));
    } else {
      updateSettings(state.copyWith(clearWatermarkLogoPath: true));
    }
  }

  void setWatermarkShowLogoForSlot(int slot, bool value) {
    if (slot == 2) {
      updateSettings(state.copyWith(watermarkShowLogo2: value));
    } else {
      updateSettings(state.copyWith(watermarkShowLogo: value));
    }
  }

  void setCoordinateFormat(CoordinateFormat format) =>
      updateSettings(state.copyWith(coordinateFormat: format));
  void setLanguage(AppLanguage lang) =>
      updateSettings(state.copyWith(language: lang));
  void setUse24HourTime(bool value) =>
      updateSettings(state.copyWith(use24HourTime: value));

  Future<void> resetToDefaults() async {
    await updateSettings(const OverlaySettings(), persistImmediately: true);
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _persistSettings(state);
    super.dispose();
  }
}

final overlaySettingsProvider =
    StateNotifierProvider<OverlaySettingsNotifier, OverlaySettings>((ref) {
  return OverlaySettingsNotifier();
});
