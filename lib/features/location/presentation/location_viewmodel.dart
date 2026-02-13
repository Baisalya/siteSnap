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
StreamProvider.autoDispose<Position>((ref) async* {

  // ✅ Check service first
  final serviceEnabled =
  await Geolocator.isLocationServiceEnabled();

  if (!serviceEnabled) {
    throw Exception("Location services disabled");
  }

  // ✅ Check permission
  final permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw Exception("Location permission denied");
  }

  // ✅ START STREAM IMMEDIATELY
  yield* Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2,
    ),
  );
});
