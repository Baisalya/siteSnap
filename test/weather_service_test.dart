import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/core/services/weather_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('surveycam/local_environment');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('formats local environmental sensor readings', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readEnvironment');
      return {
        'temperatureCelsius': 24.4,
        'humidityPercent': 64.6,
        'pressureHpa': 1012.7,
      };
    });

    final data = await WeatherService.fetchWeather(1, 2);

    expect(data, isNotNull);
    expect(data!.temp, '24\u00B0C');
    expect(data.humidity, '65%');
    expect(data.pressure, '1013 hPa');
    expect(data.airQuality, isNull);
  });

  test('reports local sensor availability', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getSensorAvailability');
      return {
        'temperature': true,
        'humidity': false,
        'pressure': true,
        'airQuality': false,
      };
    });

    final availability = await WeatherService.getLocalSensorAvailability();

    expect(availability.temperature, isTrue);
    expect(availability.humidity, isFalse);
    expect(availability.pressure, isTrue);
    expect(availability.airQuality, isFalse);
  });

  test('returns null when no local environmental sensors are available',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => <String, dynamic>{});

    final data = await WeatherService.fetchWeather(1, 2);

    expect(data, isNull);
  });
}
