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
      coordinateFormat: coordinateFormat ?? this.coordinateFormat,
      language: language ?? this.language,
      use24HourTime: use24HourTime ?? this.use24HourTime,
    );
  }
}
