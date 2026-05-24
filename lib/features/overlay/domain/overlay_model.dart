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

  factory OverlayData.fromJson(Map<String, dynamic> json) {
    return OverlayData(
      dateTime: json['dateTime'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      altitude: (json['altitude'] as num?)?.toDouble() ?? 0,
      heading: (json['heading'] as num?)?.toDouble() ?? 0,
      direction: json['direction'] as String? ?? '',
      note: json['note'] as String? ?? '',
      locationWarning: json['locationWarning'] as String?,
      weather: json['weather'] as String?,
      humidity: json['humidity'] as String?,
      air: json['air'] as String?,
      pressure: json['pressure'] as String?,
      position: WatermarkPosition.values[
          (json['position'] as int? ?? WatermarkPosition.bottomLeft.index)
              .clamp(0, WatermarkPosition.values.length - 1)],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dateTime': dateTime,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'heading': heading,
      'direction': direction,
      'note': note,
      'locationWarning': locationWarning,
      'weather': weather,
      'humidity': humidity,
      'air': air,
      'pressure': pressure,
      'position': position.index,
    };
  }

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
