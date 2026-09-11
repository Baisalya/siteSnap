import 'package:geolocator/geolocator.dart';

abstract class LocationRepository {
  Future<Position> getLocation();
  Future<Position?> getLastKnownLocation();
  Stream<Position> watchLocation();
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermission> checkPermission();
}
