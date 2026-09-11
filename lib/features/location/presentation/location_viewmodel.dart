import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:geolocator/geolocator.dart';
import 'package:surveycam/core/di/providers.dart';
import 'package:surveycam/features/location/domain/location_fix.dart';

/// Keeps the last valid fix in memory while the process is alive. It is only
/// reused after location service + permission are revalidated and the fix is
/// still recent enough for [LocationFixPolicy.bootstrapMaxAge].
final latestLocationSnapshotProvider = StateProvider<Position?>((ref) => null);

/// The camera toggles this with its lifecycle. Auto-dispose then cancels the
/// native position stream while the app is backgrounded, avoiding unnecessary
/// GPS/battery/thermal work.
final locationTrackingActiveProvider = StateProvider<bool>((ref) => true);

/// =======================================================
/// SINGLE LOCATION FETCH
/// =======================================================
final locationViewModelProvider = FutureProvider<Position>((ref) async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();

  if (!serviceEnabled) {
    throw Exception('Location services disabled');
  }

  final permission = await Geolocator.checkPermission();

  if (permission != LocationPermission.whileInUse &&
      permission != LocationPermission.always) {
    throw Exception('Location permission not granted');
  }

  return ref.read(locationRepositoryProvider).getLocation();
});

/// =======================================================
/// LOW-LATENCY CAMERA LOCATION FEED
/// =======================================================
final locationStreamProvider =
    StreamProvider.autoDispose<LocationFix>((ref) async* {
  if (!ref.watch(locationTrackingActiveProvider)) {
    return;
  }

  final repository = ref.read(locationRepositoryProvider);
  var disposed = false;
  ref.onDispose(() => disposed = true);

  Position? lastEmitted;
  var bootstrapAttempted = false;
  LocationFixStatus? lastStatus;

  void remember(Position position) {
    if (disposed) {
      return;
    }
    ref.read(latestLocationSnapshotProvider.notifier).state = position;
  }

  while (!disposed) {
    // Run independent native checks concurrently. This is only done when a
    // stream needs to start/recover, not for every location update.
    final serviceFuture = repository.isLocationServiceEnabled();
    final permissionFuture = repository.checkPermission();
    final serviceEnabled = await serviceFuture;
    final permission = await permissionFuture;
    if (disposed) {
      return;
    }

    if (!serviceEnabled) {
      bootstrapAttempted = false;
      lastEmitted = null;
      ref.read(latestLocationSnapshotProvider.notifier).state = null;
      if (lastStatus != LocationFixStatus.serviceDisabled) {
        lastStatus = LocationFixStatus.serviceDisabled;
        yield const LocationFix.serviceDisabled();
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      continue;
    }

    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      bootstrapAttempted = false;
      lastEmitted = null;
      ref.read(latestLocationSnapshotProvider.notifier).state = null;
      if (lastStatus != LocationFixStatus.permissionDenied) {
        lastStatus = LocationFixStatus.permissionDenied;
        yield const LocationFix.permissionDenied();
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      continue;
    }

    if (!bootstrapAttempted) {
      bootstrapAttempted = true;
      final memoryFix = ref.read(latestLocationSnapshotProvider);
      Position? bootstrap =
          memoryFix != null && LocationFixPolicy.isFreshBootstrap(memoryFix)
              ? memoryFix
              : null;

      if (bootstrap == null) {
        try {
          final cached = await repository.getLastKnownLocation();
          if (disposed) {
            return;
          }
          if (cached != null && LocationFixPolicy.isFreshBootstrap(cached)) {
            bootstrap = cached;
          }
        } catch (_) {
          // A cache miss/failure is not a camera error; the live stream below
          // remains authoritative.
        }
      }

      if (bootstrap != null) {
        lastEmitted = bootstrap;
        lastStatus = LocationFixStatus.ready;
        remember(bootstrap);
        if (disposed) {
          return;
        }
        yield LocationFix.ready(bootstrap, fromCache: true);
      } else {
        lastStatus = LocationFixStatus.fetching;
        yield const LocationFix.fetching();
      }
    }

    try {
      await for (final position in repository.watchLocation()) {
        if (disposed) {
          return;
        }
        if (!LocationFixPolicy.hasUsableCoordinates(position)) {
          continue;
        }

        lastEmitted = position;
        lastStatus = LocationFixStatus.ready;
        remember(position);
        if (disposed) {
          return;
        }
        yield LocationFix.ready(position);
      }
    } catch (_) {
      // Keep a valid on-screen fix during a transient provider restart instead
      // of flashing 0/0. Only show "Fetching" when no usable fix exists.
      if (lastEmitted == null && lastStatus != LocationFixStatus.fetching) {
        lastStatus = LocationFixStatus.fetching;
        yield const LocationFix.fetching();
      }
    }

    if (disposed) {
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
});
