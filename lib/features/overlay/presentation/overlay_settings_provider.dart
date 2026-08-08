import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surveycam/core/monetization/premium_feature.dart';
import 'package:surveycam/core/monetization/premium_policy.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';

class OverlaySettingsNotifier extends StateNotifier<OverlaySettings> {
  OverlaySettingsNotifier() : super(const OverlaySettings()) {
    _loadFuture = _loadSettings().catchError((Object error, StackTrace stack) {
      debugPrint('Overlay settings load failed: $error\n$stack');
    }).whenComplete(() => _loadComplete = true);
  }

  Timer? _persistTimer;
  late final Future<void> _loadFuture;
  bool _loadComplete = false;

  Future<void> get ready => _loadFuture;

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

    final loaded = OverlaySettings(
      backgroundColor: Color(colorValue),
      textColor: Color(textColorValue),
      backgroundOpacity: opacity.clamp(0.0, 1.0).toDouble(),
      showDateTime: showDateTime,
      showCoordinates: showCoordinates,
      showAltitude: showAltitude,
      showDirection: showDirection,
      showNote: showNote,
      showWeather: showWeather,
      showHumidity: showHumidity,
      showAir: showAir,
      showPressure: showPressure,
      watermarkPresetIndex: watermarkPresetIndex.clamp(0, 2),
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
    if (mounted) {
      state = loaded;
    }
  }

  Future<void> updateSettings(
    OverlaySettings settings, {
    bool persistImmediately = false,
  }) async {
    await ready;
    if (!mounted) return;
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

  Future<void> _apply(
    OverlaySettings Function(OverlaySettings current) transform, {
    bool persistImmediately = false,
  }) async {
    await ready;
    await updateSettings(
      transform(state),
      persistImmediately: persistImmediately,
    );
  }

  Future<void> setBackgroundColor(Color color) =>
      _apply((current) => current.copyWith(backgroundColor: color));
  Future<void> setTextColor(Color color) =>
      _apply((current) => current.copyWith(textColor: color));
  Future<void> setBackgroundOpacity(double opacity) => _apply(
        (current) => current.copyWith(
          backgroundOpacity: opacity.clamp(0.0, 1.0).toDouble(),
        ),
      );
  Future<void> setShowDateTime(bool value) =>
      _apply((current) => current.copyWith(showDateTime: value));
  Future<void> setShowCoordinates(bool value) =>
      _apply((current) => current.copyWith(showCoordinates: value));
  Future<void> setShowAltitude(bool value) =>
      _apply((current) => current.copyWith(showAltitude: value));
  Future<void> setShowDirection(bool value) =>
      _apply((current) => current.copyWith(showDirection: value));
  Future<void> setShowNote(bool value) =>
      _apply((current) => current.copyWith(showNote: value));
  Future<void> setShowWeather(bool value) =>
      _apply((current) => current.copyWith(showWeather: value));
  Future<void> setShowHumidity(bool value) =>
      _apply((current) => current.copyWith(showHumidity: value));
  Future<void> setShowAir(bool value) =>
      _apply((current) => current.copyWith(showAir: value));
  Future<void> setShowPressure(bool value) =>
      _apply((current) => current.copyWith(showPressure: value));
  Future<void> setWatermarkPresetIndex(int value) =>
      _apply((current) => current.copyWith(watermarkPresetIndex: value));
  Future<void> setWatermarkTextForSlot(int slot, String value) {
    return _apply(
      (current) => slot == 2
          ? current.copyWith(watermarkText2: value)
          : current.copyWith(watermarkText: value),
    );
  }

  Future<void> setWatermarkLogoPathForSlot(int slot, String value) {
    return _apply(
      (current) => slot == 2
          ? current.copyWith(
              watermarkLogoPath2: value,
              watermarkShowLogo2: true,
            )
          : current.copyWith(
              watermarkLogoPath: value,
              watermarkShowLogo: true,
            ),
      persistImmediately: true,
    );
  }

  Future<void> clearWatermarkLogoPathForSlot(int slot) {
    return _apply(
      (current) => slot == 2
          ? current.copyWith(clearWatermarkLogoPath2: true)
          : current.copyWith(clearWatermarkLogoPath: true),
      persistImmediately: true,
    );
  }

  Future<void> setWatermarkShowLogoForSlot(int slot, bool value) {
    return _apply(
      (current) => slot == 2
          ? current.copyWith(watermarkShowLogo2: value)
          : current.copyWith(watermarkShowLogo: value),
    );
  }

  Future<void> setCoordinateFormat(CoordinateFormat format) =>
      _apply((current) => current.copyWith(coordinateFormat: format));
  Future<void> setLanguage(AppLanguage lang) =>
      _apply((current) => current.copyWith(language: lang));
  Future<void> setUse24HourTime(bool value) =>
      _apply((current) => current.copyWith(use24HourTime: value));

  Future<void> resetToDefaults() async {
    await updateSettings(const OverlaySettings(), persistImmediately: true);
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    if (_loadComplete) {
      unawaited(_persistSettings(state));
    }
    super.dispose();
  }
}

final overlaySettingsProvider =
    StateNotifierProvider<OverlaySettingsNotifier, OverlaySettings>((ref) {
  return OverlaySettingsNotifier();
});

final effectiveOverlaySettingsProvider = Provider<OverlaySettings>((ref) {
  final settings = ref.watch(overlaySettingsProvider);
  final canUseCustomBranding =
      ref.watch(premiumPolicyProvider).canUse(PremiumFeature.customBranding);
  if (canUseCustomBranding || settings.watermarkPresetIndex == 0) {
    return settings;
  }
  return settings.copyWith(watermarkPresetIndex: 0);
});
