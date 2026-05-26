import 'dart:async';

import 'package:flutter/services.dart';

class WeatherData {
  final String? temp;
  final String? humidity;
  final String? airQuality;
  final String? pressure;

  const WeatherData({
    this.temp,
    this.humidity,
    this.airQuality,
    this.pressure,
  });

  bool get hasAnyValue =>
      temp != null ||
      humidity != null ||
      airQuality != null ||
      pressure != null;
}

class EnvironmentSensorAvailability {
  final bool temperature;
  final bool humidity;
  final bool pressure;
  final bool airQuality;

  const EnvironmentSensorAvailability({
    this.temperature = false,
    this.humidity = false,
    this.pressure = false,
    this.airQuality = false,
  });

  factory EnvironmentSensorAvailability.fromMap(Map<dynamic, dynamic> data) {
    return EnvironmentSensorAvailability(
      temperature: data['temperature'] == true,
      humidity: data['humidity'] == true,
      pressure: data['pressure'] == true,
      airQuality: data['airQuality'] == true,
    );
  }
}

class _LocalEnvironmentReadings {
  final double? temperatureCelsius;
  final double? humidityPercent;
  final double? pressureHpa;

  const _LocalEnvironmentReadings({
    this.temperatureCelsius,
    this.humidityPercent,
    this.pressureHpa,
  });

  factory _LocalEnvironmentReadings.fromMap(Map<dynamic, dynamic> data) {
    return _LocalEnvironmentReadings(
      temperatureCelsius: _asDouble(data['temperatureCelsius']),
      humidityPercent: _asDouble(data['humidityPercent']),
      pressureHpa: _asDouble(data['pressureHpa']),
    );
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return null;
  }
}

class WeatherService {
  static const MethodChannel _channel =
      MethodChannel('surveycam/local_environment');

  static Future<EnvironmentSensorAvailability>
      getLocalSensorAvailability() async {
    try {
      final result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>(
            'getSensorAvailability',
          )
          .timeout(const Duration(seconds: 2));

      if (result == null) return const EnvironmentSensorAvailability();
      return EnvironmentSensorAvailability.fromMap(result);
    } on TimeoutException {
      return const EnvironmentSensorAvailability();
    } on PlatformException {
      return const EnvironmentSensorAvailability();
    } on MissingPluginException {
      return const EnvironmentSensorAvailability();
    }
  }

  static Future<WeatherData?> fetchWeather(double lat, double lon) async {
    final readings = await _readLocalEnvironment();
    if (readings == null) return null;

    final weatherData = WeatherData(
      temp: _formatTemperature(readings.temperatureCelsius),
      humidity: _formatHumidity(readings.humidityPercent),
      pressure: _formatPressure(readings.pressureHpa),
      airQuality: null,
    );

    return weatherData.hasAnyValue ? weatherData : null;
  }

  static Future<_LocalEnvironmentReadings?> _readLocalEnvironment() async {
    try {
      final result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>(
            'readEnvironment',
          )
          .timeout(const Duration(seconds: 2));

      if (result == null) return null;
      return _LocalEnvironmentReadings.fromMap(result);
    } on TimeoutException {
      return null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static String? _formatTemperature(double? celsius) {
    if (celsius == null || celsius < -80 || celsius > 80) return null;
    return '${celsius.round()}\u00B0C';
  }

  static String? _formatHumidity(double? percent) {
    if (percent == null || percent < 0 || percent > 100) return null;
    return '${percent.round()}%';
  }

  static String? _formatPressure(double? hpa) {
    if (hpa == null || hpa < 300 || hpa > 1200) return null;
    return '${hpa.round()} hPa';
  }
}
