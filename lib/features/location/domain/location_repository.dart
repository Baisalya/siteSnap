import 'package:geolocator/geolocator.dart';

abstract class LocationRepository {
  Future<Position> getLocation();
}
