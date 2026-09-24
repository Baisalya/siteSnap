import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:surveycam/core/di/providers.dart';
import 'package:surveycam/core/services/location_service.dart';
import 'package:surveycam/features/location/domain/location_fix.dart';
import 'package:surveycam/features/location/presentation/location_viewmodel.dart';

enum MonetizationMarket {
  india,
  other,
  unknown;

  static MonetizationMarket fromCountryCode(String? countryCode) {
    final normalized = countryCode?.trim().toUpperCase();
    if (normalized == null || normalized.isEmpty) {
      return MonetizationMarket.unknown;
    }
    return normalized == 'IN'
        ? MonetizationMarket.india
        : MonetizationMarket.other;
  }
}

/// Uses a recent GPS fix instead of Play Billing's country API (which Google
/// prohibits using for marketing/ad targeting). If the country cannot be
/// verified, rewarded access fails closed and the subscription remains usable.
final monetizationMarketProvider =
    FutureProvider<MonetizationMarket>((ref) async {
  try {
    var position = ref.read(latestLocationSnapshotProvider);
    if (position == null || !LocationFixPolicy.isFreshBootstrap(position)) {
      final repository = ref.read(locationRepositoryProvider);
      final serviceEnabled = await repository.isLocationServiceEnabled();
      final permission = await repository.checkPermission();
      if (!serviceEnabled ||
          (permission != LocationPermission.whileInUse &&
              permission != LocationPermission.always)) {
        return MonetizationMarket.unknown;
      }

      final cached = await repository.getLastKnownLocation();
      position = cached != null && LocationFixPolicy.isFreshBootstrap(cached)
          ? cached
          : await repository.getLocation().timeout(const Duration(seconds: 8));
    }

    if (!LocationFixPolicy.hasUsableCoordinates(position)) {
      return MonetizationMarket.unknown;
    }
    final countryCode = await LocationService.getCountryCode(
      position.latitude,
      position.longitude,
    ).timeout(const Duration(seconds: 8));
    return MonetizationMarket.fromCountryCode(countryCode);
  } catch (_) {
    return MonetizationMarket.unknown;
  }
});
