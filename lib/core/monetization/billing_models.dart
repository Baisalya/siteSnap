enum StorePurchaseStatus { pending, purchased, restored, canceled, error }

class BillingProduct {
  const BillingProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.displayPrice,
    required this.currencyCode,
    required this.basePlanId,
    required this.offerId,
    required this.offerToken,
    required this.hasFreeTrial,
    required this.freeTrialPeriod,
    required this.renewalPrice,
    required this.renewalPeriod,
    required this.storeDetails,
  });

  final String id;
  final String title;
  final String description;
  final String displayPrice;
  final String currencyCode;
  final String? basePlanId;
  final String? offerId;
  final String? offerToken;
  final bool hasFreeTrial;
  final String? freeTrialPeriod;
  final String renewalPrice;
  final String? renewalPeriod;
  final Object storeDetails;
}

class StorePurchase {
  const StorePurchase({
    required this.productId,
    required this.status,
    required this.purchaseId,
    required this.transactionDate,
    required this.serverVerificationData,
    required this.localVerificationData,
    required this.verificationSource,
    required this.pendingCompletePurchase,
    required this.errorMessage,
    required this.storeDetails,
  });

  final String productId;
  final StorePurchaseStatus status;
  final String? purchaseId;
  final String? transactionDate;
  final String serverVerificationData;
  final String localVerificationData;
  final String verificationSource;
  final bool pendingCompletePurchase;
  final String? errorMessage;
  final Object storeDetails;
}

enum EntitlementSource { none, cached, playStore }

class BillingState {
  const BillingState({
    this.isInitializing = true,
    this.storeAvailable = false,
    this.isRestoring = false,
    this.purchasePending = false,
    this.isPro = false,
    this.verificationConfigured = false,
    this.entitlementSource = EntitlementSource.none,
    this.product,
    this.message,
    this.error,
  });

  final bool isInitializing;
  final bool storeAvailable;
  final bool isRestoring;
  final bool purchasePending;
  final bool isPro;
  final bool verificationConfigured;
  final EntitlementSource entitlementSource;
  final BillingProduct? product;
  final String? message;
  final String? error;

  BillingState copyWith({
    bool? isInitializing,
    bool? storeAvailable,
    bool? isRestoring,
    bool? purchasePending,
    bool? isPro,
    bool? verificationConfigured,
    EntitlementSource? entitlementSource,
    BillingProduct? product,
    bool clearProduct = false,
    String? message,
    bool clearMessage = false,
    String? error,
    bool clearError = false,
  }) {
    return BillingState(
      isInitializing: isInitializing ?? this.isInitializing,
      storeAvailable: storeAvailable ?? this.storeAvailable,
      isRestoring: isRestoring ?? this.isRestoring,
      purchasePending: purchasePending ?? this.purchasePending,
      isPro: isPro ?? this.isPro,
      verificationConfigured:
          verificationConfigured ?? this.verificationConfigured,
      entitlementSource: entitlementSource ?? this.entitlementSource,
      product: clearProduct ? null : product ?? this.product,
      message: clearMessage ? null : message ?? this.message,
      error: clearError ? null : error ?? this.error,
    );
  }
}
