import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import 'package:geolocator/geolocator.dart';

final locationViewModelProvider =
FutureProvider<Position>((ref) async {
  return ref.read(locationRepositoryProvider).getLocation();
});


final locationStreamProvider =
StreamProvider<Position>((ref) {
  return Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 2,
    ),
  );
});
