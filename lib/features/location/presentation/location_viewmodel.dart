import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/di/providers.dart';

/// =======================================================
/// SINGLE LOCATION FETCH (USED WHEN NEEDED)
/// =======================================================
final locationViewModelProvider =
FutureProvider<Position>((ref) async {

  final permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw Exception("Location permission not granted");
  }

  return ref.read(locationRepositoryProvider).getLocation();
});


/// =======================================================
/// LIVE LOCATION STREAM (FIXED VERSION)
/// =======================================================
final locationStreamProvider =
StreamProvider.autoDispose<Position>((ref) async* {

  /// ✅ Check if location service (GPS) is enabled
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();

  if (!serviceEnabled) {
    throw Exception("Location services disabled");
  }

  /// ✅ Check permission AFTER user grants it
  final permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw Exception("Location permission denied");
  }

  /// ✅ Start stream only when everything OK
  yield* Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2,
    ),
  );
});
