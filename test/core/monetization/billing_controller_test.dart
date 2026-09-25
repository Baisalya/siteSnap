import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/core/monetization/billing_client.dart';
import 'package:surveycam/core/monetization/billing_controller.dart';
import 'package:surveycam/core/monetization/billing_models.dart';
import 'package:surveycam/core/monetization/entitlement_storage.dart';
import 'package:surveycam/core/monetization/premium_config.dart';
import 'package:surveycam/core/monetization/purchase_verifier.dart';

final _now = DateTime.utc(2026, 8, 8, 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('verified restored subscription grants and acknowledges Pro', () async {
    final purchase = _purchase(
      status: StorePurchaseStatus.restored,
      pendingCompletePurchase: true,
    );
    final client = _FakeBillingClient(restored: [purchase]);
    final storage = _MemoryEntitlementStorage();
    final controller = BillingController(
      client: client,
      verifier: _FakeVerifier(active: true),
      storage: storage,
      now: () => _now,
    );
    addTearDown(controller.dispose);
    addTearDown(client.dispose);

    await controller.initialize();

    expect(controller.state.isPro, isTrue);
    expect(controller.state.entitlementSource, EntitlementSource.playStore);
    expect(
      controller.state.entitlementExpiresAt,
      _now.add(const Duration(days: 365)),
    );
    expect(client.completed, [purchase]);
    expect(storage.value?.isActive, isTrue);
    expect(storage.value?.verifiedAt, _now);
  });

  test('invalid server verification never grants or acknowledges Pro',
      () async {
    final purchase = _purchase(
      status: StorePurchaseStatus.purchased,
      pendingCompletePurchase: true,
    );
    final client = _FakeBillingClient(restored: [purchase]);
    final controller = BillingController(
      client: client,
      verifier: _FakeVerifier(active: false),
      storage: _MemoryEntitlementStorage(),
      now: () => _now,
    );
    addTearDown(controller.dispose);
    addTearDown(client.dispose);

    await controller.initialize();

    expect(controller.state.isPro, isFalse);
    expect(client.completed, isEmpty);
    expect(controller.state.error, contains('not active'));
  });

  test('pending purchase does not unlock Pro', () async {
    final client = _FakeBillingClient(
      restored: [_purchase(status: StorePurchaseStatus.pending)],
    );
    final controller = BillingController(
      client: client,
      verifier: _FakeVerifier(active: true),
      storage: _MemoryEntitlementStorage(),
      now: () => _now,
    );
    addTearDown(controller.dispose);
    addTearDown(client.dispose);

    await controller.initialize();

    expect(controller.state.isPro, isFalse);
    expect(controller.state.purchasePending, isTrue);
  });

  test('definitive empty restore revokes a cached entitlement', () async {
    final storage = _MemoryEntitlementStorage(
      CachedEntitlement(
        isActive: true,
        verifiedAt: _now.subtract(const Duration(hours: 1)),
      ),
    );
    final client = _FakeBillingClient();
    final controller = BillingController(
      client: client,
      verifier: _FakeVerifier(active: true),
      storage: storage,
      now: () => _now,
    );
    addTearDown(controller.dispose);
    addTearDown(client.dispose);

    await controller.initialize();

    expect(controller.state.isPro, isFalse);
    expect(storage.value, isNull);
  });

  test('temporary Play outage preserves a fresh cached entitlement', () async {
    final storage = _MemoryEntitlementStorage(
      CachedEntitlement(
        isActive: true,
        verifiedAt: _now.subtract(const Duration(days: 1)),
      ),
    );
    final client = _FakeBillingClient(available: false);
    final controller = BillingController(
      client: client,
      verifier: _FakeVerifier(active: true),
      storage: storage,
      now: () => _now,
    );
    addTearDown(controller.dispose);
    addTearDown(client.dispose);

    await controller.initialize();

    expect(controller.state.isPro, isTrue);
    expect(controller.state.entitlementSource, EntitlementSource.cached);
    expect(storage.value, isNotNull);
  });

  test('temporary verification outage during restore preserves cached Pro',
      () async {
    final storage = _MemoryEntitlementStorage(
      CachedEntitlement(
        isActive: true,
        verifiedAt: _now.subtract(const Duration(days: 1)),
      ),
    );
    final client = _FakeBillingClient(
      restored: [_purchase(status: StorePurchaseStatus.restored)],
    );
    final controller = BillingController(
      client: client,
      verifier: const _FakeVerifier(active: false, definitive: false),
      storage: storage,
      now: () => _now,
    );
    addTearDown(controller.dispose);
    addTearDown(client.dispose);

    await controller.initialize();
    await controller.restore();

    expect(controller.state.isPro, isTrue);
    expect(controller.state.entitlementSource, EntitlementSource.cached);
    expect(storage.value, isNotNull);
  });

  test('configured launch offer is selected over other annual offers',
      () async {
    final desired = _product(offerId: PremiumConfig.launchOfferId);
    final client = _FakeBillingClient(
      products: [
        _product(offerId: 'another-offer'),
        desired,
      ],
    );
    final controller = BillingController(
      client: client,
      verifier: _FakeVerifier(active: true),
      storage: _MemoryEntitlementStorage(),
      now: () => _now,
    );
    addTearDown(controller.dispose);
    addTearDown(client.dispose);

    await controller.initialize();

    expect(controller.state.product, same(desired));
  });

  test('buy launches Google Play with the selected subscription offer',
      () async {
    final desired = _product(offerId: PremiumConfig.launchOfferId);
    final client = _FakeBillingClient(products: [desired]);
    final controller = BillingController(
      client: client,
      verifier: _FakeVerifier(active: true),
      storage: _MemoryEntitlementStorage(),
      now: () => _now,
    );
    addTearDown(controller.dispose);
    addTearDown(client.dispose);
    await controller.initialize();

    await controller.buyPro();

    expect(client.purchased, [desired]);
    expect(controller.state.purchasePending, isTrue);
  });

  test('anonymous Play cancellation clears a pending purchase', () async {
    final client = _FakeBillingClient();
    final controller = BillingController(
      client: client,
      verifier: _FakeVerifier(active: true),
      storage: _MemoryEntitlementStorage(),
      now: () => _now,
    );
    addTearDown(controller.dispose);
    addTearDown(client.dispose);
    await controller.initialize();

    await controller.buyPro();
    client.emit([
      _purchase(
        status: StorePurchaseStatus.canceled,
        productId: '',
      ),
    ]);
    await pumpEventQueue();

    expect(controller.state.purchasePending, isFalse);
    expect(controller.state.message, 'Purchase cancelled.');
  });

  test('anonymous Play payment error clears a pending purchase', () async {
    final client = _FakeBillingClient();
    final controller = BillingController(
      client: client,
      verifier: _FakeVerifier(active: true),
      storage: _MemoryEntitlementStorage(),
      now: () => _now,
    );
    addTearDown(controller.dispose);
    addTearDown(client.dispose);
    await controller.initialize();

    await controller.buyPro();
    client.emit([
      _purchase(
        status: StorePurchaseStatus.error,
        productId: '',
        errorMessage: 'Payment declined.',
      ),
    ]);
    await pumpEventQueue();

    expect(controller.state.purchasePending, isFalse);
    expect(controller.state.error, 'Payment declined.');
  });

  test('anonymous terminal updates are ignored without a pending checkout',
      () async {
    final client = _FakeBillingClient();
    final controller = BillingController(
      client: client,
      verifier: _FakeVerifier(active: true),
      storage: _MemoryEntitlementStorage(),
      now: () => _now,
    );
    addTearDown(controller.dispose);
    addTearDown(client.dispose);
    await controller.initialize();

    client.emit([
      _purchase(
        status: StorePurchaseStatus.error,
        productId: '',
        errorMessage: 'Unrelated billing error.',
      ),
    ]);
    await pumpEventQueue();

    expect(controller.state.purchasePending, isFalse);
    expect(controller.state.error, isNull);
  });

  test('unsupported stores cannot grant or restore Google Play entitlement',
      () async {
    final client = _FakeBillingClient(
      supported: false,
      restored: [_purchase(status: StorePurchaseStatus.restored)],
    );
    final controller = BillingController(
      client: client,
      verifier: _FakeVerifier(active: true),
      storage: _MemoryEntitlementStorage(),
      now: () => _now,
    );
    addTearDown(controller.dispose);
    addTearDown(client.dispose);

    await controller.initialize();
    await controller.restore();

    expect(controller.state.isPro, isFalse);
    expect(controller.state.error, contains('Android only'));
  });
}

BillingProduct _product({String? offerId}) {
  return BillingProduct(
    id: PremiumConfig.proProductId,
    title: 'SurveyCam Pro',
    description: 'Pro',
    displayPrice: '₹199.00',
    currencyCode: 'INR',
    basePlanId: PremiumConfig.annualBasePlanId,
    offerId: offerId,
    offerToken: 'token-$offerId',
    hasFreeTrial: true,
    freeTrialPeriod: 'P1Y',
    renewalPrice: '₹199.00',
    renewalPeriod: 'P1Y',
    storeDetails: Object(),
  );
}

StorePurchase _purchase({
  required StorePurchaseStatus status,
  String productId = PremiumConfig.proProductId,
  bool pendingCompletePurchase = false,
  String? errorMessage,
}) {
  return StorePurchase(
    productId: productId,
    status: status,
    purchaseId: 'purchase-id',
    transactionDate: '1',
    serverVerificationData: 'play-token',
    localVerificationData: 'local-data',
    verificationSource: 'google_play',
    pendingCompletePurchase: pendingCompletePurchase,
    errorMessage: errorMessage,
    storeDetails: Object(),
  );
}

class _FakeBillingClient implements BillingClient {
  _FakeBillingClient({
    this.supported = true,
    this.available = true,
    this.products = const [],
    this.restored = const [],
  });

  final bool supported;
  final bool available;
  final List<BillingProduct> products;
  final List<StorePurchase> restored;
  final completed = <StorePurchase>[];
  final purchased = <BillingProduct>[];
  final _streamController = StreamController<List<StorePurchase>>.broadcast();

  @override
  bool get isSupported => supported;

  @override
  Stream<List<StorePurchase>> get purchaseStream => _streamController.stream;

  @override
  Future<void> completePurchase(StorePurchase purchase) async {
    completed.add(purchase);
  }

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> purchase(BillingProduct product) async {
    purchased.add(product);
    return true;
  }

  @override
  Future<List<BillingProduct>> queryProducts(Set<String> productIds) async {
    return products.isEmpty ? [_product()] : products;
  }

  @override
  Future<List<StorePurchase>> restorePurchases() async => restored;

  void emit(List<StorePurchase> purchases) {
    _streamController.add(purchases);
  }

  Future<void> dispose() => _streamController.close();
}

class _FakeVerifier implements PurchaseVerifier {
  const _FakeVerifier({required this.active, this.definitive = true});

  final bool active;
  final bool definitive;

  @override
  String? get configurationMessage => null;

  @override
  bool get isConfigured => true;

  @override
  Future<PurchaseVerificationResult> verify(StorePurchase purchase) async {
    return PurchaseVerificationResult(
      isValid: active,
      isActive: active,
      isDefinitive: definitive,
      expiresAt: _now.add(const Duration(days: 365)),
      message: active ? null : 'Subscription is not active.',
    );
  }
}

class _MemoryEntitlementStorage implements EntitlementStorage {
  _MemoryEntitlementStorage([this.value]);

  CachedEntitlement? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<CachedEntitlement?> load() async => value;

  @override
  Future<void> save(CachedEntitlement entitlement) async => value = entitlement;
}
