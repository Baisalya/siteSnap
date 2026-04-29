import 'package:flutter/material.dart';

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
    );
  }
}
