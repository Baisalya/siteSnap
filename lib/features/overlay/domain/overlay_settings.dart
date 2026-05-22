import 'package:flutter/material.dart';

enum CoordinateFormat { decimal, dms }

enum AppLanguage { en, de, ru, hi, es, fr, pt, it }

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
    this.language = AppLanguage.en,
    this.use24HourTime = true,
  });

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
