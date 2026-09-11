import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:surveycam/features/location/domain/location_fix.dart';

Position _position({
  required double latitude,
  required double longitude,
  required DateTime timestamp,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: timestamp,
    accuracy: 4,
    altitude: 12,
    altitudeAccuracy: 3,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  group('LocationFixPolicy', () {
    final now = DateTime(2026, 9, 10, 12);

    test('accepts recent cached fix for immediate camera bootstrap', () {
      final position = _position(
        latitude: 20.2707,
        longitude: 86.1840,
        timestamp: now.subtract(const Duration(minutes: 2)),
      );

      expect(LocationFixPolicy.isFreshBootstrap(position, now: now), isTrue);
    });

    test('rejects stale cached fix', () {
      final position = _position(
        latitude: 20.2707,
        longitude: 86.1840,
        timestamp: now.subtract(const Duration(minutes: 6)),
      );

      expect(LocationFixPolicy.isFreshBootstrap(position, now: now), isFalse);
    });

    test('rejects impossible future cached timestamp', () {
      final position = _position(
        latitude: 20.2707,
        longitude: 86.1840,
        timestamp: now.add(const Duration(minutes: 1)),
      );

      expect(LocationFixPolicy.isFreshBootstrap(position, now: now), isFalse);
    });

    test('rejects only the uninitialized zero-zero coordinate', () {
      expect(
        LocationFixPolicy.hasUsableCoordinates(
          _position(latitude: 0, longitude: 0, timestamp: now),
        ),
        isFalse,
      );
      expect(
        LocationFixPolicy.hasUsableCoordinates(
          _position(latitude: 0, longitude: 86.1840, timestamp: now),
        ),
        isTrue,
      );
      expect(
        LocationFixPolicy.hasUsableCoordinates(
          _position(latitude: 20.2707, longitude: 0, timestamp: now),
        ),
        isTrue,
      );
    });

    test('rejects out-of-range coordinates', () {
      expect(
        LocationFixPolicy.hasUsableCoordinates(
          _position(latitude: 91, longitude: 86, timestamp: now),
        ),
        isFalse,
      );
      expect(
        LocationFixPolicy.hasUsableCoordinates(
          _position(latitude: 20, longitude: 181, timestamp: now),
        ),
        isFalse,
      );
    });
  });
}
