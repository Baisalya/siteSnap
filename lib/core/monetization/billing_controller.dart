import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'billing_client.dart';
import 'billing_models.dart';
import 'entitlement_storage.dart';
import 'play_billing_client.dart';
import 'premium_config.dart';
import 'purchase_verifier.dart';

final billingClientProvider = Provider<BillingClient>((ref) {
  return PlayBillingClient();
});

final purchaseVerifierProvider = Provider<PurchaseVerifier>((ref) {
  return PlayPurchaseVerifier();
});

final entitlementStorageProvider = Provider<EntitlementStorage>((ref) {
  return SharedPreferencesEntitlementStorage();
});

final billingControllerProvider =
    StateNotifierProvider<BillingController, BillingState>((ref) {
  return BillingController(
    client: ref.watch(billingClientProvider),
    verifier: ref.watch(purchaseVerifierProvider),
    storage: ref.watch(entitlementStorageProvider),
  );
});

/// Shared by the permanent membership entry and its details screen. Free-launch
/// builds must not start Google Play Billing just to display account navigation.
final proMembershipBillingProvider = Provider<BillingState>((ref) {
  if (PremiumConfig.freeLaunchMode) {
    return const BillingState(isInitializing: false);
  }
  return ref.watch(billingControllerProvider);
});

class BillingController extends StateNotifier<BillingState> {
  BillingController({
    required BillingClient client,
    required PurchaseVerifier verifier,
    required EntitlementStorage storage,
    DateTime Function()? now,
  })  : _client = client,
        _verifier = verifier,
        _storage = storage,
        _now = now ?? DateTime.now,
        super(BillingState(verificationConfigured: verifier.isConfigured)) {
    if (_client.isSupported) {
      _purchaseSubscription = _client.purchaseStream.listen(
        (purchases) => _enqueue(() => _processPurchases(purchases)),
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Play purchase stream error: $error\n$stackTrace');
          if (mounted) {
            state = state.copyWith(
              purchasePending: false,
              error:
                  'Google Play purchase updates are temporarily unavailable.',
            );
          }
        },
      );
    }
    unawaited(initialize());
  }

  final BillingClient _client;
  final PurchaseVerifier _verifier;
  final EntitlementStorage _storage;
  final DateTime Function() _now;
  StreamSubscription<List<StorePurchase>>? _purchaseSubscription;
  Future<void> _queue = Future<void>.value();
  Future<void>? _initialization;

  Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    final cached = await _storage.load();
    final cachedIsUsable = cached?.isUsableAt(
          _now(),
          PremiumConfig.offlineEntitlementGrace,
        ) ??
        false;
    if (mounted && cachedIsUsable) {
      state = state.copyWith(
        isPro: true,
        entitlementSource: EntitlementSource.cached,
        entitlementExpiresAt: cached?.expiresAt,
      );
    }

    if (!_client.isSupported) {
      if (mounted) {
        state = state.copyWith(
          isInitializing: false,
          error:
              'SurveyCam Pro subscriptions are currently available on Android only.',
        );
      }
      return;
    }

    try {
      final available = await _client.isAvailable();
      if (!mounted) return;
      state = state.copyWith(storeAvailable: available);
      if (!available) {
        state = state.copyWith(
          isInitializing: false,
          error: cachedIsUsable
              ? 'Google Play is offline. Cached Pro access is being used.'
              : 'Google Play Billing is unavailable.',
        );
        return;
      }

      final products = await _client.queryProducts({
        PremiumConfig.proProductId,
      });
      final product = _selectProduct(products);
      if (!mounted) return;
      state = state.copyWith(
        product: product,
        clearProduct: product == null,
        error: product == null
            ? 'The SurveyCam Pro subscription is not available for this account or region.'
            : null,
        clearError: product != null,
      );

      final restored = await _client.restorePurchases();
      final result = await _processPurchases(restored);
      if (!result.hasActive &&
          !result.hasTransientFailure &&
          (restored.isEmpty || result.hasDefinitiveInactive)) {
        await _revokeEntitlement();
      }
    } catch (error, stackTrace) {
      debugPrint('Billing initialization failed: $error\n$stackTrace');
      if (mounted) {
        state = state.copyWith(
          error: cachedIsUsable
              ? 'Google Play could not refresh. Cached Pro access is being used.'
              : 'Could not connect to Google Play Billing.',
        );
      }
    } finally {
      if (mounted) state = state.copyWith(isInitializing: false);
    }
  }

  BillingProduct? _selectProduct(List<BillingProduct> products) {
    final candidates = products
        .where((product) => product.id == PremiumConfig.proProductId)
        .toList();
    if (candidates.isEmpty) return null;

    BillingProduct? find(bool Function(BillingProduct product) predicate) {
      for (final product in candidates) {
        if (predicate(product)) return product;
      }
      return null;
    }

    return find((product) =>
            product.basePlanId == PremiumConfig.annualBasePlanId &&
            product.offerId == PremiumConfig.launchOfferId) ??
        find((product) =>
            product.basePlanId == PremiumConfig.annualBasePlanId &&
            product.hasFreeTrial) ??
        find((product) =>
            product.basePlanId == PremiumConfig.annualBasePlanId &&
            product.offerId == null) ??
        candidates.first;
  }

  Future<void> buyPro() async {
    await initialize();
    if (state.purchasePending) return;
    if (!_verifier.isConfigured) {
      state = state.copyWith(error: _verifier.configurationMessage);
      return;
    }
    final product = state.product;
    if (!state.storeAvailable || product == null) {
      state = state.copyWith(
        error: 'SurveyCam Pro is not currently available from Google Play.',
      );
      return;
    }

    state = state.copyWith(
      purchasePending: true,
      clearError: true,
      message: 'Opening Google Play checkout…',
    );
    try {
      final launched = await _client.purchase(product);
      if (!launched && mounted) {
        // FIX: If Google Play fails to launch the checkout window (e.g. system error),
        // reset the pending state immediately so the button is not stuck on loading.
        state = state.copyWith(
          purchasePending: false,
          error: 'Google Play could not start the purchase.',
          clearMessage: true,
        );
      }
    } catch (error) {
      if (mounted) {
        // FIX: Ensure pending state is cleared if the purchase launch throws an exception.
        state = state.copyWith(
          purchasePending: false,
          error: 'Purchase could not start: $error',
          clearMessage: true,
        );
      }
    }
  }

  Future<void> restore() async {
    if (state.isRestoring) return;
    if (!_client.isSupported) {
      state = state.copyWith(
        error: 'SurveyCam Pro subscriptions are available on Android only.',
      );
      return;
    }
    state = state.copyWith(
      isRestoring: true,
      clearError: true,
      message: 'Checking Google Play purchases…',
    );
    try {
      if (!await _client.isAvailable()) {
        throw StateError('Google Play Billing is unavailable.');
      }
      if (mounted) state = state.copyWith(storeAvailable: true);
      if (state.product == null) {
        final products = await _client.queryProducts({
          PremiumConfig.proProductId,
        });
        final product = _selectProduct(products);
        if (mounted) {
          state = state.copyWith(
            product: product,
            clearProduct: product == null,
          );
        }
      }
      final purchases = await _client.restorePurchases();
      final result = await _processPurchases(purchases);
      if (!result.hasActive && !result.hasTransientFailure) {
        await _revokeEntitlement();
        if (mounted) {
          state = state.copyWith(
            message: 'No active SurveyCam Pro subscription was found.',
          );
        }
      }
    } catch (error) {
      if (mounted) state = state.copyWith(error: 'Restore failed: $error');
    } finally {
      if (mounted) state = state.copyWith(isRestoring: false);
    }
  }

  Future<_PurchaseBatchResult> _processPurchases(
    List<StorePurchase> purchases,
  ) async {
    var foundActive = false;
    var foundTransientFailure = false;
    var foundDefinitiveInactive = false;
    for (final purchase in purchases) {
      final isProPurchase = purchase.productId == PremiumConfig.proProductId;
      final isAnonymousTerminalUpdate = state.purchasePending &&
          purchase.productId.isEmpty &&
          (purchase.status == StorePurchaseStatus.canceled ||
              purchase.status == StorePurchaseStatus.error);
      if (!isProPurchase && !isAnonymousTerminalUpdate) continue;

      switch (purchase.status) {
        case StorePurchaseStatus.pending:
          if (mounted) {
            state = state.copyWith(
              purchasePending: true,
              message: 'The Google Play payment is pending.',
              clearError: true,
            );
          }
        case StorePurchaseStatus.canceled:
          if (mounted) {
            // FIX: Clear the loading/pending state when a user manually cancels
            // the purchase from the Google Play sheet (e.g. by pressing Back).
            state = state.copyWith(
              purchasePending: false,
              message: 'Purchase cancelled.',
              clearError: true,
            );
          }
        case StorePurchaseStatus.error:
          if (mounted) {
            // FIX: Clear the loading/pending state if Google Play reports an error
            // during the checkout flow (e.g. declined payment).
            state = state.copyWith(
              purchasePending: false,
              error: purchase.errorMessage ??
                  'Google Play reported a purchase error.',
              clearMessage: true,
            );
          }
        case StorePurchaseStatus.purchased:
        case StorePurchaseStatus.restored:
          final verification = await _verifier.verify(purchase);
          if (!verification.isValid || !verification.isActive) {
            if (verification.isDefinitive) {
              foundDefinitiveInactive = true;
            } else {
              foundTransientFailure = true;
            }
            if (mounted) {
              state = state.copyWith(
                purchasePending: false,
                error: verification.message ??
                    'Google Play could not verify an active subscription.',
                clearMessage: true,
              );
            }
            continue;
          }

          foundActive = true;
          await _storage.save(CachedEntitlement(
            isActive: true,
            verifiedAt: _now(),
            expiresAt: verification.expiresAt,
          ));
          if (purchase.pendingCompletePurchase) {
            await _client.completePurchase(purchase);
          }
          if (mounted) {
            state = state.copyWith(
              isPro: true,
              purchasePending: false,
              entitlementSource: EntitlementSource.playStore,
              entitlementExpiresAt: verification.expiresAt,
              message: purchase.status == StorePurchaseStatus.restored
                  ? 'SurveyCam Pro restored.'
                  : 'SurveyCam Pro activated.',
              clearError: true,
            );
          }
      }
    }
    return _PurchaseBatchResult(
      hasActive: foundActive,
      hasTransientFailure: foundTransientFailure,
      hasDefinitiveInactive: foundDefinitiveInactive,
    );
  }

  Future<void> _revokeEntitlement() async {
    await _storage.clear();
    if (mounted) {
      state = state.copyWith(
        isPro: false,
        entitlementSource: EntitlementSource.none,
        clearEntitlementExpiresAt: true,
      );
    }
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final completer = Completer<void>();
    _queue = _queue.catchError((_) {}).then((_) async {
      try {
        await action();
        completer.complete();
      } catch (error, stackTrace) {
        debugPrint('Purchase update handling failed: $error\n$stackTrace');
        if (mounted) {
          state = state.copyWith(
            purchasePending: false,
            error: 'The purchase could not be processed safely.',
          );
        }
        // Stream callbacks have no caller awaiting this future. Record the
        // failure in state without emitting an unhandled asynchronous error.
        completer.complete();
      }
    });
    return completer.future;
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }
}

class _PurchaseBatchResult {
  const _PurchaseBatchResult({
    required this.hasActive,
    required this.hasTransientFailure,
    required this.hasDefinitiveInactive,
  });

  final bool hasActive;
  final bool hasTransientFailure;
  final bool hasDefinitiveInactive;
}
