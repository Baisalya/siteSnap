import 'billing_models.dart';

abstract interface class BillingClient {
  bool get isSupported;

  Stream<List<StorePurchase>> get purchaseStream;

  Future<bool> isAvailable();

  Future<List<BillingProduct>> queryProducts(Set<String> productIds);

  Future<bool> purchase(BillingProduct product);

  Future<List<StorePurchase>> restorePurchases();

  Future<void> completePurchase(StorePurchase purchase);
}
