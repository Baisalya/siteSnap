class OverlayData {
  final String dateTime;
  final double lat;
  final double lng;
  final double altitude;
  final String direction;
  final String note;

  OverlayData({
    required this.dateTime,
    required this.lat,
    required this.lng,
    required this.altitude,
    required this.direction,
    required this.note,
  });

  OverlayData copyWith({
    String? dateTime,
    double? lat,
    double? lng,
    double? altitude,
    String? direction,
    String? note,
  }) {
    return OverlayData(
      dateTime: dateTime ?? this.dateTime,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      altitude: altitude ?? this.altitude,
      direction: direction ?? this.direction,
      note: note ?? this.note,
    );
  }
}
