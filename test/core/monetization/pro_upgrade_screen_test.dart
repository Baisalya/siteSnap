import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
