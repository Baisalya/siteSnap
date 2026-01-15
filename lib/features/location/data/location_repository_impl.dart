import 'package:geolocator/geolocator.dart';
import '../domain/location_repository.dart';

class LocationRepositoryImpl implements LocationRepository {
  @override
  Future<Position> getLocation() async {
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }
}
