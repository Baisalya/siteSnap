import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/camera/data/camera_repository_impl.dart';
import '../../features/location/data/location_repository_impl.dart';

final cameraRepositoryProvider = Provider<CameraRepositoryImpl>((ref) {
  return CameraRepositoryImpl();
});

final locationRepositoryProvider = Provider<LocationRepositoryImpl>((ref) {
  return LocationRepositoryImpl();
});
