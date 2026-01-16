class OverlayData {
  final String dateTime;
  final double lat;
  final double lng;
  final double altitude;

  /// Compass
  final double heading;   // 0–360
  final String direction; // N, NE, E, etc.

  /// User note
  final String note;

  const OverlayData({
    required this.dateTime,
    required this.lat,
    required this.lng,
    required this.altitude,
    required this.heading,
    required this.direction,
    required this.note,
  });

  OverlayData copyWith({
    String? dateTime,
    double? lat,
    double? lng,
    double? altitude,
    double? heading,
    String? direction,
    String? note,
  }) {
    return OverlayData(
      dateTime: dateTime ?? this.dateTime,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      altitude: altitude ?? this.altitude,
      heading: heading ?? this.heading,
      direction: direction ?? this.direction,
      note: note ?? this.note,
    );
  }
}
