import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surveycam/privacypolicy/PrivacyDialog.dart';
import 'package:surveycam/privacypolicy/privacyProvider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PrivacyNotifier Tests', () {
    late ProviderContainer container;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('Initial state is null (loading)', () {
      // Accessing the notifier starts the loading process
      container.read(privacyProvider.notifier);
      expect(container.read(privacyProvider), null);
    });

    test('State becomes false if no value in SharedPreferences', () async {
      container.read(privacyProvider.notifier);

      // Wait for the next microtask or a short delay to allow SharedPreferences to complete
      await pumpEventQueue();

      expect(container.read(privacyProvider), false);
    });

    test('acceptPolicy updates state and persists value', () async {
      final notifier = container.read(privacyProvider.notifier);
      await pumpEventQueue(); // Wait for initial load

      await notifier.acceptPolicy();

      expect(container.read(privacyProvider), true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('privacyAccepted'), true);
      expect(
        prefs.getInt('privacyPolicyVersion'),
        PrivacyNotifier.currentPolicyVersion,
      );
    });

    test('State loads true if already accepted in SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'privacyAccepted': true,
        'privacyPolicyVersion': PrivacyNotifier.currentPolicyVersion,
      });

      final newContainer = ProviderContainer();
      addTearDown(newContainer.dispose);

      newContainer.read(privacyProvider.notifier);
      await pumpEventQueue();

      expect(newContainer.read(privacyProvider), true);
    });

    test('older accepted policy is shown again after a policy update',
        () async {
      SharedPreferences.setMockInitialValues({
        'privacyAccepted': true,
        'privacyPolicyVersion': PrivacyNotifier.currentPolicyVersion - 1,
      });

      final newContainer = ProviderContainer();
      addTearDown(newContainer.dispose);
      newContainer.read(privacyProvider.notifier);
      await pumpEventQueue();

      expect(newContainer.read(privacyProvider), false);
    });

    test('resetPolicy removes value and sets state to false', () async {
      SharedPreferences.setMockInitialValues({
        'privacyAccepted': true,
        'privacyPolicyVersion': PrivacyNotifier.currentPolicyVersion,
      });
      final newContainer = ProviderContainer();
      addTearDown(newContainer.dispose);

      final notifier = newContainer.read(privacyProvider.notifier);
      await pumpEventQueue();
      expect(newContainer.read(privacyProvider), true);

      await notifier.resetPolicy();

      expect(newContainer.read(privacyProvider), false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('privacyAccepted'), null);
      expect(prefs.getInt('privacyPolicyVersion'), null);
    });
  });

  testWidgets('privacy dialog fits a short phone viewport', (tester) async {
    tester.view.physicalSize = const Size(400, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: PrivacyDialog()),
      ),
    );
    await tester.pump();

    final layoutException = tester.takeException();
    expect(
      layoutException,
      isNull,
      reason: layoutException is FlutterError
          ? layoutException.toStringDeep()
          : layoutException?.toString(),
    );
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('ACCEPT'), findsOneWidget);
  });
}
