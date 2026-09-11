import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:surveycam/core/di/providers.dart';
import 'package:surveycam/features/location/domain/location_fix.dart';
import 'package:surveycam/features/location/domain/location_repository.dart';
import 'package:surveycam/features/location/presentation/location_viewmodel.dart';

Position _position(DateTime timestamp) {
  return Position(
    latitude: 20.2707,
    longitude: 86.1840,
    timestamp: timestamp,
    accuracy: 5,
    altitude: 12,
    altitudeAccuracy: 3,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

class _FakeLocationRepository implements LocationRepository {
  _FakeLocationRepository({this.cached});

  final Position? cached;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getLocation() async => cached ?? _position(DateTime.now());

  @override
  Future<Position?> getLastKnownLocation() async => cached;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Stream<Position> watchLocation() => Stream<Position>.empty();
}

Future<LocationFix> _readFirstLocationFix(ProviderContainer container) async {
  // StreamProvider.autoDispose must be observed while its async bootstrap is
  // running. A bare container.read(provider.future) does not retain an
  // external listener, so Riverpod is free to dispose the provider before the
  // repository's service/permission/cache futures complete. The production
  // camera uses ref.listen, so keep an equivalent subscription alive here and
  // assert the first emitted LocationFix from that real lifecycle.
  final subscription = container.listen<AsyncValue<LocationFix>>(
    locationStreamProvider,
    (_, __) {},
  );
  try {
    return await container.read(locationStreamProvider.future);
  } finally {
    subscription.close();
  }
}

void main() {
  test('recent last-known fix is first event instead of an artificial null',
      () async {
    final cached =
        _position(DateTime.now().subtract(const Duration(minutes: 1)));
    final container = ProviderContainer(
      overrides: [
        locationRepositoryProvider.overrideWithValue(
          _FakeLocationRepository(cached: cached),
        ),
      ],
    );
    addTearDown(container.dispose);

    final first = await _readFirstLocationFix(container);

    expect(first.status, LocationFixStatus.ready);
    expect(first.fromCache, isTrue);
    expect(first.position?.latitude, cached.latitude);
    expect(first.position?.longitude, cached.longitude);
  });

  test('cache miss reports fetching while live provider acquires a fix',
      () async {
    final container = ProviderContainer(
      overrides: [
        locationRepositoryProvider.overrideWithValue(_FakeLocationRepository()),
      ],
    );
    addTearDown(container.dispose);

    final first = await _readFirstLocationFix(container);

    expect(first.status, LocationFixStatus.fetching);
    expect(first.position, isNull);
  });
}
