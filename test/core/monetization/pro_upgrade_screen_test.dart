import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/core/monetization/billing_models.dart';
import 'package:surveycam/core/monetization/premium_config.dart';
import 'package:surveycam/core/monetization/pro_upgrade_screen.dart';

void main() {
  testWidgets('Pro screen fits a compact phone and explains free colors',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ProUpgradeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Pro is included'), findsOneWidget);
    expect(find.textContaining('white/black overlay colors'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('Pro overlay colors'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Pro overlay colors'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.byKey(const Key('pro-primary-cta')),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pro-primary-cta')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active subscriber sees professional membership details',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final product = BillingProduct(
      id: PremiumConfig.proProductId,
      title: 'SurveyCam Pro',
      description: 'Professional field workflow',
      displayPrice: '₹199.00',
      currencyCode: 'INR',
      basePlanId: PremiumConfig.annualBasePlanId,
      offerId: PremiumConfig.launchOfferId,
      offerToken: 'test-offer-token',
      hasFreeTrial: true,
      freeTrialPeriod: 'P1Y',
      renewalPrice: '₹199.00',
      renewalPeriod: 'P1Y',
      storeDetails: Object(),
    );
    final billing = BillingState(
      isInitializing: false,
      storeAvailable: true,
      isPro: true,
      verificationConfigured: true,
      entitlementSource: EntitlementSource.playStore,
      entitlementExpiresAt: DateTime(2027, 8, 8),
      product: product,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ProUpgradeScreen(billingOverride: billing),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pro-membership-details')), findsOneWidget);
    expect(find.byKey(const Key('pro-membership-status')), findsOneWidget);
    expect(find.text('Membership details'), findsOneWidget);
    expect(find.text('SurveyCam Pro · Annual'), findsOneWidget);
    expect(find.text('Google Play verified'), findsOneWidget);
    expect(find.text('Active through 8 Aug 2027'), findsOneWidget);
    expect(find.textContaining('Join by'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
