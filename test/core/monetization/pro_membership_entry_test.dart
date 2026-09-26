import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/core/monetization/billing_controller.dart';
import 'package:surveycam/core/monetization/billing_models.dart';
import 'package:surveycam/core/monetization/premium_config.dart';
import 'package:surveycam/core/monetization/pro_membership_entry.dart';
import 'package:surveycam/core/monetization/pro_upgrade_screen.dart';

void main() {
  Future<void> showEntry(
    WidgetTester tester,
    BillingState billing, {
    bool compact = false,
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [proMembershipBillingProvider.overrideWithValue(billing)],
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: compact ? 180 : 320,
                child: ProMembershipEntry(compact: compact, enabled: enabled),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final compact in [true, false]) {
    testWidgets(
        '${compact ? 'camera badge' : 'settings card'} opens active membership',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await showEntry(
        tester,
        BillingState(
          isInitializing: false,
          isPro: true,
          entitlementSource: EntitlementSource.playStore,
          entitlementExpiresAt: DateTime(2027, 8, 8),
        ),
        compact: compact,
      );

      expect(find.text('Pro Active'), findsOneWidget);
      await tester.tap(find.byKey(Key(
        compact ? 'camera-pro-membership' : 'settings-pro-membership',
      )));
      await tester.pumpAndSettle();

      expect(find.byType(ProUpgradeScreen), findsOneWidget);
      expect(find.byKey(const Key('pro-membership-status')), findsOneWidget);
      expect(find.text('Active through 8 Aug 2027'), findsOneWidget);
      expect(find.text('Watch ad & continue'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('details follow a restored entitlement without reopening',
      (tester) async {
    final state = StateProvider<BillingState>((ref) => const BillingState());
    final container = ProviderContainer(overrides: [
      proMembershipBillingProvider.overrideWith((ref) => ref.watch(state)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: ProMembershipEntry()),
      ),
    ));
    await tester.pump();
    expect(find.text('Checking Pro'), findsOneWidget);
    expect(find.text('Get Pro'), findsNothing);
    await tester.tap(find.byKey(const Key('settings-pro-membership')));
    // The monetized screen intentionally has an indeterminate checking spinner.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    container.read(state.notifier).state = const BillingState(
      isInitializing: false,
      isPro: true,
      entitlementSource: EntitlementSource.playStore,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pro-membership-details')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Pro Active'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cached Pro stays active during background refresh',
      (tester) async {
    await showEntry(
        tester,
        const BillingState(
          isPro: true,
          isRestoring: true,
          entitlementSource: EntitlementSource.cached,
        ));
    expect(find.text('Pro Active'), findsOneWidget);
    expect(find.textContaining('Refreshing'), findsOneWidget);
    expect(find.text('Get Pro'), findsNothing);
  });

  testWidgets('non-Pro entry remains available without a premium gate',
      (tester) async {
    await showEntry(tester, const BillingState(isInitializing: false));
    expect(find.text('My Subscription'), findsOneWidget);
    expect(find.text(PremiumConfig.freeLaunchMode ? 'Pro included' : 'Get Pro'),
        findsOneWidget);
    expect(find.text('Pro Active'), findsNothing);
    await tester.tap(find.byKey(const Key('settings-pro-membership')));
    // No store product is supplied in this fixture; price loading can animate.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ProUpgradeScreen), findsOneWidget);
    if (!PremiumConfig.freeLaunchMode) {
      await tester.scrollUntilVisible(find.text('Restore purchase'), 300);
      expect(find.text('Restore purchase'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending purchase is not presented as paid Pro', (tester) async {
    await showEntry(
        tester,
        const BillingState(
          isInitializing: false,
          purchasePending: true,
        ));
    expect(find.text('Payment pending'), findsOneWidget);
    expect(find.text('Pro Active'), findsNothing);
  });

  testWidgets('camera membership navigation is disabled while recording',
      (tester) async {
    await showEntry(
        tester, const BillingState(isInitializing: false, isPro: true),
        compact: true, enabled: false);
    await tester.tap(find.byKey(const Key('camera-pro-membership')));
    await tester.pumpAndSettle();
    expect(find.byType(ProUpgradeScreen), findsNothing);
  });

  testWidgets('membership controls fit small widths and large text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        proMembershipBillingProvider.overrideWithValue(const BillingState(
          isInitializing: false,
          error: 'Google Play temporarily unavailable',
        )),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 180, child: ProMembershipEntry(compact: true)),
              ProMembershipEntry(),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    if (!PremiumConfig.freeLaunchMode) {
      expect(find.text('Check Pro status'), findsNWidgets(2));
      expect(find.text('Get Pro'), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('subscription CTA waits for restore before offering purchase',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
          home: ProUpgradeScreen(
        billingOverride: BillingState(isInitializing: false, isRestoring: true),
      )),
    ));
    await tester.pump();
    await tester.scrollUntilVisible(
        find.byKey(const Key('pro-primary-cta')), 300);
    if (!PremiumConfig.freeLaunchMode) {
      expect(find.text('Checking subscription…'), findsOneWidget);
      expect(find.text('Subscribe to Pro'), findsNothing);
      expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('pro-primary-cta')))
              .onPressed,
          isNull);
    }
    expect(tester.takeException(), isNull);
  });

  test('free launch membership navigation does not initialize billing', () {
    if (!PremiumConfig.freeLaunchMode) return;
    final container = ProviderContainer(overrides: [
      billingControllerProvider.overrideWith((ref) {
        throw StateError('Free launch must not connect to Google Play');
      }),
    ]);
    addTearDown(container.dispose);
    expect(
        container.read(proMembershipBillingProvider).isInitializing, isFalse);
    expect(container.read(proMembershipBillingProvider).isPro, isFalse);
  });
}
