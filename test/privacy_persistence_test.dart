import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    });

    test('State loads true if already accepted in SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'privacyAccepted': true});
      
      final newContainer = ProviderContainer();
      addTearDown(newContainer.dispose);
      
      newContainer.read(privacyProvider.notifier);
      await pumpEventQueue();
      
      expect(newContainer.read(privacyProvider), true);
    });

    test('resetPolicy removes value and sets state to false', () async {
      SharedPreferences.setMockInitialValues({'privacyAccepted': true});
      final newContainer = ProviderContainer();
      addTearDown(newContainer.dispose);
      
      final notifier = newContainer.read(privacyProvider.notifier);
      await pumpEventQueue();
      expect(newContainer.read(privacyProvider), true);
      
      await notifier.resetPolicy();
      
      expect(newContainer.read(privacyProvider), false);
      
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('privacyAccepted'), null);
    });
  });
}
