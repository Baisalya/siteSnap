import 'WatermarkPosition.dart';

class OverlayData {
  final String dateTime;
  final double latitude;
  final double longitude;
  final double altitude;
  final double heading;
  final String direction;
  final String note;
  final String? locationWarning;

  final String? weather;
  final String? humidity;
  final String? air;
  final String? pressure;

  final WatermarkPosition position;

  const OverlayData({
    required this.dateTime,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.heading,
    required this.direction,
    required this.note,
    this.locationWarning,
    this.weather,
    this.humidity,
    this.air,
    this.pressure,
    this.position = WatermarkPosition.bottomLeft,
  });

  OverlayData copyWith({
    String? dateTime,
    double? latitude,
    double? longitude,
    double? altitude,
    double? heading,
    String? direction,
    String? note,
    String? locationWarning,
    bool clearLocationWarning = false,
    String? weather,
    String? humidity,
    String? air,
    String? pressure,
    WatermarkPosition? position,
  }) {
    return OverlayData(
      dateTime: dateTime ?? this.dateTime,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      heading: heading ?? this.heading,
      direction: direction ?? this.direction,
      note: note ?? this.note,
      locationWarning: clearLocationWarning
          ? null
          : (locationWarning ?? this.locationWarning),
      weather: weather ?? this.weather,
      humidity: humidity ?? this.humidity,
      air: air ?? this.air,
      pressure: pressure ?? this.pressure,
      position: position ?? this.position,
    );
  }
}
