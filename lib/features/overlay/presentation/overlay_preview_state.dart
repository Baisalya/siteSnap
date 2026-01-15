import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/overlay_model.dart';

final overlayPreviewProvider =
StateProvider<OverlayData>((ref) {
  return OverlayData(
    dateTime: '',
    lat: 0,
    lng: 0,
    altitude: 0,
    direction: 'N',
    note: '',
  );
});
