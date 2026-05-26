import 'package:flutter/material.dart';

enum CoordinateFormat { decimal, dms }

enum AppLanguage { auto, en, de, ru, hi, es, fr, pt, it }

class OverlaySettings {
  final Color backgroundColor;
  final Color textColor;
  final double backgroundOpacity;
  final bool showDateTime;
  final bool showCoordinates;
  final bool showAltitude;
  final bool showDirection;
  final bool showNote;
  final bool showWeather;
  final bool showHumidity;
  final bool showAir;
  final bool showPressure;
  final int watermarkPresetIndex;
  final String watermarkText;
  final String? watermarkLogoPath;
  final bool watermarkShowLogo;
  final String watermarkText2;
  final String? watermarkLogoPath2;
  final bool watermarkShowLogo2;

  final CoordinateFormat coordinateFormat;
  final AppLanguage language;
  final bool use24HourTime;

  const OverlaySettings({
    this.backgroundColor = Colors.white,
    this.textColor = Colors.black,
    this.backgroundOpacity = 0.85,
    this.showDateTime = true,
    this.showCoordinates = true,
    this.showAltitude = true,
    this.showDirection = true,
    this.showNote = true,
    this.showWeather = false,
    this.showHumidity = false,
    this.showAir = false,
    this.showPressure = false,
    this.watermarkPresetIndex = 0,
    this.watermarkText = '',
    this.watermarkLogoPath,
    this.watermarkShowLogo = true,
    this.watermarkText2 = '',
    this.watermarkLogoPath2,
    this.watermarkShowLogo2 = true,
    this.coordinateFormat = CoordinateFormat.decimal,
    this.language = AppLanguage.auto,
    this.use24HourTime = true,
  });

  factory OverlaySettings.fromJson(Map<String, dynamic> json) {
    return OverlaySettings(
      backgroundColor:
          Color(json['backgroundColor'] as int? ?? Colors.white.toARGB32()),
      textColor: Color(json['textColor'] as int? ?? Colors.black.toARGB32()),
      backgroundOpacity:
          (json['backgroundOpacity'] as num?)?.toDouble() ?? 0.85,
      showDateTime: json['showDateTime'] as bool? ?? true,
      showCoordinates: json['showCoordinates'] as bool? ?? true,
      showAltitude: json['showAltitude'] as bool? ?? true,
      showDirection: json['showDirection'] as bool? ?? true,
      showNote: json['showNote'] as bool? ?? true,
      showWeather: json['showWeather'] as bool? ?? false,
      showHumidity: json['showHumidity'] as bool? ?? false,
      showAir: json['showAir'] as bool? ?? false,
      showPressure: json['showPressure'] as bool? ?? false,
      watermarkPresetIndex:
          ((json['watermarkPresetIndex'] as num?)?.toInt() ?? 0)
              .clamp(0, 2)
              .toInt(),
      watermarkText: json['watermarkText'] as String? ?? '',
      watermarkLogoPath: json['watermarkLogoPath'] as String?,
      watermarkShowLogo: json['watermarkShowLogo'] as bool? ?? true,
      watermarkText2: json['watermarkText2'] as String? ?? '',
      watermarkLogoPath2: json['watermarkLogoPath2'] as String?,
      watermarkShowLogo2: json['watermarkShowLogo2'] as bool? ?? true,
      coordinateFormat: CoordinateFormat.values[
          (json['coordinateFormat'] as int? ?? CoordinateFormat.decimal.index)
              .clamp(0, CoordinateFormat.values.length - 1)],
      language: AppLanguage.values[
          (json['language'] as int? ?? AppLanguage.auto.index)
              .clamp(0, AppLanguage.values.length - 1)],
      use24HourTime: json['use24HourTime'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'backgroundColor': backgroundColor.toARGB32(),
      'textColor': textColor.toARGB32(),
      'backgroundOpacity': backgroundOpacity,
      'showDateTime': showDateTime,
      'showCoordinates': showCoordinates,
      'showAltitude': showAltitude,
      'showDirection': showDirection,
      'showNote': showNote,
      'showWeather': showWeather,
      'showHumidity': showHumidity,
      'showAir': showAir,
      'showPressure': showPressure,
      'watermarkPresetIndex': watermarkPresetIndex,
      'watermarkText': watermarkText,
      'watermarkLogoPath': watermarkLogoPath,
      'watermarkShowLogo': watermarkShowLogo,
      'watermarkText2': watermarkText2,
      'watermarkLogoPath2': watermarkLogoPath2,
      'watermarkShowLogo2': watermarkShowLogo2,
      'coordinateFormat': coordinateFormat.index,
      'language': language.index,
      'use24HourTime': use24HourTime,
    };
  }

  OverlaySettings copyWith({
    Color? backgroundColor,
    Color? textColor,
    double? backgroundOpacity,
    bool? showDateTime,
    bool? showCoordinates,
    bool? showAltitude,
    bool? showDirection,
    bool? showNote,
    bool? showWeather,
    bool? showHumidity,
    bool? showAir,
    bool? showPressure,
    int? watermarkPresetIndex,
    String? watermarkText,
    String? watermarkLogoPath,
    bool clearWatermarkLogoPath = false,
    bool? watermarkShowLogo,
    String? watermarkText2,
    String? watermarkLogoPath2,
    bool clearWatermarkLogoPath2 = false,
    bool? watermarkShowLogo2,
    CoordinateFormat? coordinateFormat,
    AppLanguage? language,
    bool? use24HourTime,
  }) {
    return OverlaySettings(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      showDateTime: showDateTime ?? this.showDateTime,
      showCoordinates: showCoordinates ?? this.showCoordinates,
      showAltitude: showAltitude ?? this.showAltitude,
      showDirection: showDirection ?? this.showDirection,
      showNote: showNote ?? this.showNote,
      showWeather: showWeather ?? this.showWeather,
      showHumidity: showHumidity ?? this.showHumidity,
      showAir: showAir ?? this.showAir,
      showPressure: showPressure ?? this.showPressure,
      watermarkPresetIndex: (watermarkPresetIndex ?? this.watermarkPresetIndex)
          .clamp(0, 2)
          .toInt(),
      watermarkText: watermarkText ?? this.watermarkText,
      watermarkLogoPath: clearWatermarkLogoPath
          ? null
          : (watermarkLogoPath ?? this.watermarkLogoPath),
      watermarkShowLogo: watermarkShowLogo ?? this.watermarkShowLogo,
      watermarkText2: watermarkText2 ?? this.watermarkText2,
      watermarkLogoPath2: clearWatermarkLogoPath2
          ? null
          : (watermarkLogoPath2 ?? this.watermarkLogoPath2),
      watermarkShowLogo2: watermarkShowLogo2 ?? this.watermarkShowLogo2,
      coordinateFormat: coordinateFormat ?? this.coordinateFormat,
      language: language ?? this.language,
      use24HourTime: use24HourTime ?? this.use24HourTime,
    );
  }

  String get activeWatermarkText {
    if (watermarkPresetIndex == 1) return watermarkText;
    if (watermarkPresetIndex == 2) return watermarkText2;
    return 'SurveyCam';
  }

  String? get activeWatermarkLogoPath {
    if (watermarkPresetIndex == 1) return watermarkLogoPath;
    if (watermarkPresetIndex == 2) return watermarkLogoPath2;
    return null;
  }

  bool get activeWatermarkShowLogo {
    if (watermarkPresetIndex == 1) return watermarkShowLogo;
    if (watermarkPresetIndex == 2) return watermarkShowLogo2;
    return true;
  }
}
