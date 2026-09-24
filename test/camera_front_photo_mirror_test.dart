import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surveycam/features/camera/presentation/camera_settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('front photo mirroring defaults on for backward compatibility', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(cameraSettingsProvider.notifier);
    await notifier.ready;

    expect(container.read(cameraSettingsProvider).mirrorFrontPhoto, isTrue);
  });

  test('front photo mirror preference persists and reloads', () async {
    final firstContainer = ProviderContainer();
    final firstNotifier = firstContainer.read(cameraSettingsProvider.notifier);
    await firstNotifier.ready;

    await firstNotifier.setMirrorFrontPhoto(false);
    expect(firstContainer.read(cameraSettingsProvider).mirrorFrontPhoto, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('mirror_front_photo'), isFalse);
    firstContainer.dispose();

    final secondContainer = ProviderContainer();
    addTearDown(secondContainer.dispose);
    final secondNotifier = secondContainer.read(cameraSettingsProvider.notifier);
    await secondNotifier.ready;

    expect(secondContainer.read(cameraSettingsProvider).mirrorFrontPhoto, isFalse);
  });
}
