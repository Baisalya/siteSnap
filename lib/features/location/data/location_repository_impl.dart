import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../domain/location_repository.dart';

class LocationRepositoryImpl implements LocationRepository {
  LocationSettings get _liveSettings {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: Duration(seconds: 2),
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );
  }

  @override
  Future<Position> getLocation() {
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        timeLimit: Duration(seconds: 8),
      ),
    );
  }

  @override
  Future<Position?> getLastKnownLocation() => Geolocator.getLastKnownPosition();

  @override
  Stream<Position> watchLocation() =>
      Geolocator.getPositionStream(locationSettings: _liveSettings);

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();
}
