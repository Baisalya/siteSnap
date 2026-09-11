import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum LocationFixStatus {
  ready,
  fetching,
  serviceDisabled,
  permissionDenied,
}

@immutable
class LocationFix {
  final LocationFixStatus status;
  final Position? position;
  final bool fromCache;

  const LocationFix._({
    required this.status,
    this.position,
    this.fromCache = false,
  });

  const LocationFix.ready(
    Position position, {
    bool fromCache = false,
  }) : this._(
          status: LocationFixStatus.ready,
          position: position,
          fromCache: fromCache,
        );

  const LocationFix.fetching() : this._(status: LocationFixStatus.fetching);

  const LocationFix.serviceDisabled()
      : this._(status: LocationFixStatus.serviceDisabled);

  const LocationFix.permissionDenied()
      : this._(status: LocationFixStatus.permissionDenied);

  bool get hasPosition => status == LocationFixStatus.ready && position != null;
}

class LocationFixPolicy {
  static const Duration bootstrapMaxAge = Duration(minutes: 5);
  static const Duration futureClockTolerance = Duration(seconds: 30);

  const LocationFixPolicy._();

  static bool hasUsableCoordinates(Position position) {
    final latitude = position.latitude;
    final longitude = position.longitude;
    if (!latitude.isFinite || !longitude.isFinite) {
      return false;
    }
    if (latitude < -90 || latitude > 90) {
      return false;
    }
    if (longitude < -180 || longitude > 180) {
      return false;
    }

    // Preserve the app's protection against the common uninitialized 0/0 fix
    // without incorrectly rejecting valid points on only the equator or only
    // the Greenwich meridian.
    return !(latitude == 0 && longitude == 0);
  }

  static bool isFreshBootstrap(
    Position position, {
    DateTime? now,
    Duration maxAge = bootstrapMaxAge,
  }) {
    if (!hasUsableCoordinates(position)) {
      return false;
    }
    final reference = now ?? DateTime.now();
    final age = reference.difference(position.timestamp);
    if (age < -futureClockTolerance) {
      return false;
    }
    return age <= maxAge;
  }
}
