import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'billing_client.dart';
import 'billing_models.dart';

class PlayBillingClient implements BillingClient {
  PlayBillingClient({InAppPurchase? store})
      : _store = store ?? InAppPurchase.instance;

  final InAppPurchase _store;

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  Stream<List<StorePurchase>> get purchaseStream =>
      _store.purchaseStream.map(_mapPurchases);

  @override
  Future<bool> isAvailable() => _store.isAvailable();

  @override
  Future<List<BillingProduct>> queryProducts(Set<String> productIds) async {
    final response = await _store.queryProductDetails(productIds);
    if (response.error != null) {
      throw StateError(response.error!.message);
    }
    return response.productDetails.map(_mapProduct).toList(growable: false);
  }

  @override
  Future<bool> purchase(BillingProduct product) {
    final details = product.storeDetails;
    if (details is! ProductDetails) {
      throw ArgumentError('Product details are not from Google Play.');
    }

    final PurchaseParam purchaseParam;
    if (details is GooglePlayProductDetails) {
      purchaseParam = GooglePlayPurchaseParam(
        productDetails: details,
        offerToken: product.offerToken ?? details.offerToken,
      );
    } else {
      purchaseParam = PurchaseParam(productDetails: details);
    }
    return _store.buyNonConsumable(purchaseParam: purchaseParam);
  }

  @override
  Future<List<StorePurchase>> restorePurchases() async {
    if (!Platform.isAndroid) {
      await _store.restorePurchases();
      return const [];
    }

    final addition =
        _store.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final response = await addition.queryPastPurchases();
    if (response.error != null) {
      throw StateError(response.error!.message);
    }
    return _mapPurchases(response.pastPurchases);
  }

  @override
  Future<void> completePurchase(StorePurchase purchase) async {
    final details = purchase.storeDetails;
    if (details is! PurchaseDetails) {
      throw ArgumentError('Purchase details are not from Google Play.');
    }
    await _store.completePurchase(details);
  }

  BillingProduct _mapProduct(ProductDetails details) {
    if (details is! GooglePlayProductDetails ||
        details.subscriptionIndex == null) {
      return BillingProduct(
        id: details.id,
        title: details.title,
        description: details.description,
        displayPrice: details.price,
        currencyCode: details.currencyCode,
        basePlanId: null,
        offerId: null,
        offerToken: null,
        hasFreeTrial: false,
        freeTrialPeriod: null,
        renewalPrice: details.price,
        renewalPeriod: null,
        storeDetails: details,
      );
    }

    final offer = details
        .productDetails.subscriptionOfferDetails![details.subscriptionIndex!];
    final phases = offer.pricingPhases;
    final freePhase =
        phases.where((phase) => phase.priceAmountMicros == 0).firstOrNull;
    final renewalPhase =
        phases.where((phase) => phase.priceAmountMicros > 0).lastOrNull;

    return BillingProduct(
      id: details.id,
      title: details.title,
      description: details.description,
      displayPrice: details.price,
      currencyCode: details.currencyCode,
      basePlanId: offer.basePlanId,
      offerId: offer.offerId,
      offerToken: offer.offerIdToken,
      hasFreeTrial: freePhase != null,
      freeTrialPeriod: freePhase?.billingPeriod,
      renewalPrice: renewalPhase?.formattedPrice ?? details.price,
      renewalPeriod: renewalPhase?.billingPeriod,
      storeDetails: details,
    );
  }

  static List<StorePurchase> _mapPurchases(
    List<PurchaseDetails> purchases,
  ) {
    return purchases.map(_mapPurchase).toList(growable: false);
  }

  static StorePurchase _mapPurchase(PurchaseDetails details) {
    return StorePurchase(
      productId: details.productID,
      status: switch (details.status) {
        PurchaseStatus.pending => StorePurchaseStatus.pending,
        PurchaseStatus.purchased => StorePurchaseStatus.purchased,
        PurchaseStatus.restored => StorePurchaseStatus.restored,
        PurchaseStatus.canceled => StorePurchaseStatus.canceled,
        PurchaseStatus.error => StorePurchaseStatus.error,
      },
      purchaseId: details.purchaseID,
      transactionDate: details.transactionDate,
      serverVerificationData: details.verificationData.serverVerificationData,
      localVerificationData: details.verificationData.localVerificationData,
      verificationSource: details.verificationData.source,
      pendingCompletePurchase: details.pendingCompletePurchase,
      errorMessage: details.error?.message,
      storeDetails: details,
    );
  }
}
