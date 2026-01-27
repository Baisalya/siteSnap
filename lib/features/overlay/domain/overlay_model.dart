class OverlayData {
  final String dateTime;
  final double Latitude;
  final double Longitude;
  final double altitude;

  /// Compass
  final double heading;   // 0–360
  final String direction; // N, NE, E, etc.

  /// User note
  final String note;

  const OverlayData({
    required this.dateTime,
    required this.Latitude,
    required this.Longitude,
    required this.altitude,
    required this.heading,
    required this.direction,
    required this.note,
  });

  OverlayData copyWith({
    String? dateTime,
    double? Latitude,
    double? Longitude,
    double? altitude,
    double? heading,
    String? direction,
    String? note,
  }) {
    return OverlayData(
      dateTime: dateTime ?? this.dateTime,
      Latitude: Latitude ?? this.Latitude,
      Longitude: Longitude ?? this.Longitude,
      altitude: altitude ?? this.altitude,
      heading: heading ?? this.heading,
      direction: direction ?? this.direction,
      note: note ?? this.note,
    );
  }
}
