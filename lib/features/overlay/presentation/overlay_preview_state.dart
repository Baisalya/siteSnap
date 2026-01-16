import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/overlay_model.dart';

final overlayPreviewProvider =
StateProvider<OverlayData>((ref) {
  return OverlayData(
    dateTime: '',
    lat: 0.0,
    lng: 0.0,
    altitude: 0.0,
    heading: 0.0,        // ✅ REQUIRED (North)
    direction: 'N',      // ✅ Cardinal direction
    note: '',
  );
});
