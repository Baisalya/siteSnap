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

      /// ✅ IMPORTANT FIX
      locationWarning: clearLocationWarning
          ? null
          : (locationWarning ?? this.locationWarning),

      position: position ?? this.position,
    );
  }
}
