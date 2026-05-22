import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherData {
  final String temp;
  final String humidity;
  final String airQuality;
  final String pressure;

  WeatherData({
    required this.temp, 
    required this.humidity, 
    required this.airQuality,
    required this.pressure,
  });
}

class WeatherService {
  // Replace with your actual API key
  static const String _apiKey = 'YOUR_OPENWEATHER_API_KEY';

  static Future<WeatherData?> fetchWeather(double lat, double lon) async {
    try {
      // Mock data for experimental features - include hPa for European standards
      return WeatherData(
        temp: "24°C Clear",
        humidity: "65%",
        airQuality: "AQI: 42 (Good)",
        pressure: "1013 hPa",
      );
    } catch (e) {
      return null;
    }
  }
}
