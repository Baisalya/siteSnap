class OverlayData {
  final String dateTime;
  final double latitude;
  final double longitude;
  final double altitude;

  /// Compass
  final double heading;   // 0–360
  final String direction; // N, NE, E, etc.

  /// User note
  final String note;

  const OverlayData({
    required this.dateTime,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.heading,
    required this.direction,
    required this.note,
  });

  OverlayData copyWith({
    String? dateTime,
    double? latitude,
    double? longitude,
    double? altitude,
    double? heading,
    String? direction,
    String? note,
  }) {
    return OverlayData(
      dateTime: dateTime ?? this.dateTime,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      heading: heading ?? this.heading,
      direction: direction ?? this.direction,
      note: note ?? this.note,
    );
  }
}
