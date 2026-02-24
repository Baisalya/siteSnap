import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/di/providers.dart';

/// =======================================================
/// SINGLE LOCATION FETCH
/// =======================================================
final locationViewModelProvider =
FutureProvider<Position>((ref) async {

  final serviceEnabled =
  await Geolocator.isLocationServiceEnabled();

  if (!serviceEnabled) {
    throw Exception("Location services disabled");
  }

  final permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw Exception("Location permission not granted");
  }

  return ref.read(locationRepositoryProvider).getLocation();
});


/// =======================================================
/// LIVE LOCATION STREAM (STABLE VERSION)
/// =======================================================
final locationStreamProvider =
StreamProvider.autoDispose<Position?>((ref) async* {

  while (true) {

    /// CHECK LOCATION SERVICE
    final serviceEnabled =
    await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      yield null;
      await Future.delayed(const Duration(seconds: 2));
      continue;
    }

    /// CHECK PERMISSION
    final permission =
    await Geolocator.checkPermission();

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      yield null;
      await Future.delayed(const Duration(seconds: 2));
      continue;
    }

    /// START GPS STREAM
    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).map((position) {

      if (position.latitude == 0 ||
          position.longitude == 0) {
        return null;
      }

      return position;
    });
  }
});




