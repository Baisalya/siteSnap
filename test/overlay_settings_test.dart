import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:surveycam/core/monetization/premium_policy.dart';
import 'package:surveycam/features/overlay/domain/overlay_model.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';
import 'package:surveycam/features/overlay/presentation/overlay_settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists brand watermark settings through json', () {
    const settings = OverlaySettings(
      watermarkPresetIndex: 2,
      watermarkText: 'My Company',
      watermarkLogoPath: '/tmp/logo.png',
      watermarkShowLogo: false,
      watermarkText2: 'Field Team',
      watermarkLogoPath2: '/tmp/logo-2.png',
      watermarkShowLogo2: true,
    );

    final roundTrip = OverlaySettings.fromJson(settings.toJson());

    expect(roundTrip.watermarkPresetIndex, 2);
    expect(roundTrip.watermarkText, 'My Company');
    expect(roundTrip.watermarkLogoPath, '/tmp/logo.png');
    expect(roundTrip.watermarkShowLogo, isFalse);
    expect(roundTrip.watermarkText2, 'Field Team');
    expect(roundTrip.watermarkLogoPath2, '/tmp/logo-2.png');
    expect(roundTrip.watermarkShowLogo2, isTrue);
    expect(roundTrip.activeWatermarkText, 'Field Team');
    expect(roundTrip.activeWatermarkLogoPath, '/tmp/logo-2.png');
  });

  test('defaults brand watermark to SurveyCam branding', () {
    final settings = OverlaySettings.fromJson({});

    expect(settings.watermarkPresetIndex, 0);
    expect(settings.activeWatermarkText, 'SurveyCam');
    expect(settings.activeWatermarkLogoPath, isNull);
    expect(settings.activeWatermarkShowLogo, isTrue);
    expect(settings.watermarkText, isEmpty);
    expect(settings.watermarkText2, isEmpty);
  });

  test('only pure white and black are permanent free overlay colors', () {
    expect(isFreeOverlayColor(const Color(0xFFFFFFFF)), isTrue);
    expect(isFreeOverlayColor(const Color(0xFF000000)), isTrue);
    expect(isFreeOverlayColor(const Color(0xFF1976D2)), isFalse);
    expect(isFreeOverlayColor(const Color(0xFFFFFFFE)), isFalse);
  });

  test('selects first custom watermark slot independently', () {
    const settings = OverlaySettings(
      watermarkPresetIndex: 1,
      watermarkText: 'Client A',
      watermarkLogoPath: '/tmp/client-a.png',
      watermarkShowLogo: false,
      watermarkText2: 'Client B',
      watermarkLogoPath2: '/tmp/client-b.png',
    );

    expect(settings.activeWatermarkText, 'Client A');
    expect(settings.activeWatermarkLogoPath, '/tmp/client-a.png');
    expect(settings.activeWatermarkShowLogo, isFalse);
  });

  test('environment values can be explicitly cleared after a failed reading',
      () {
    const data = OverlayData(
      dateTime: '',
      latitude: 0,
      longitude: 0,
      altitude: 0,
      heading: 0,
      direction: 'N',
      note: '',
      weather: '25°C',
      humidity: '70%',
      air: 'Good',
      pressure: '1000 hPa',
    );

    final cleared = data.copyWith(
      clearWeather: true,
      clearHumidity: true,
      clearAir: true,
      clearPressure: true,
    );

    expect(cleared.weather, isNull);
    expect(cleared.humidity, isNull);
    expect(cleared.air, isNull);
    expect(cleared.pressure, isNull);
  });

  test('effective settings enforce the centralized custom-branding gate',
      () async {
    final container = ProviderContainer(
      overrides: [
        premiumPolicyProvider.overrideWithValue(
          const PremiumPolicy(freeLaunchMode: false),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(overlaySettingsProvider.notifier);
    await notifier.ready;
    await notifier.setWatermarkPresetIndex(1);

    expect(container.read(overlaySettingsProvider).watermarkPresetIndex, 1);
    expect(
      container.read(effectiveOverlaySettingsProvider).watermarkPresetIndex,
      0,
    );
  });

  test('effective settings replace paid colors when Pro is unavailable',
      () async {
    final container = ProviderContainer(
      overrides: [
        premiumPolicyProvider.overrideWithValue(
          const PremiumPolicy(freeLaunchMode: false),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(overlaySettingsProvider.notifier);
    await notifier.ready;
    await notifier.updateSettings(
      const OverlaySettings(
        backgroundColor: Color(0xFF1976D2),
        textColor: Color(0xFFFFF9C4),
      ),
      persistImmediately: true,
    );

    final saved = container.read(overlaySettingsProvider);
    final effective = container.read(effectiveOverlaySettingsProvider);

    expect(saved.backgroundColor, const Color(0xFF1976D2));
    expect(saved.textColor, const Color(0xFFFFF9C4));
    expect(effective.backgroundColor, Colors.white);
    expect(effective.textColor, Colors.black);
  });

  test('effective settings preserve white and black without Pro', () async {
    final container = ProviderContainer(
      overrides: [
        premiumPolicyProvider.overrideWithValue(
          const PremiumPolicy(freeLaunchMode: false),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(overlaySettingsProvider.notifier);
    await notifier.ready;
    await notifier.updateSettings(
      const OverlaySettings(
        backgroundColor: Colors.black,
        textColor: Colors.white,
      ),
      persistImmediately: true,
    );

    final effective = container.read(effectiveOverlaySettingsProvider);

    expect(effective.backgroundColor, Colors.black);
    expect(effective.textColor, Colors.white);
  });

  test('effective settings preserve paid colors for Pro members', () async {
    final container = ProviderContainer(
      overrides: [
        premiumPolicyProvider.overrideWithValue(
          const PremiumPolicy(
            freeLaunchMode: false,
            userHasProPurchase: true,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(overlaySettingsProvider.notifier);
    await notifier.ready;
    await notifier.updateSettings(
      const OverlaySettings(
        backgroundColor: Color(0xFF1976D2),
        textColor: Color(0xFFFFF9C4),
      ),
      persistImmediately: true,
    );

    final effective = container.read(effectiveOverlaySettingsProvider);

    expect(effective.backgroundColor, const Color(0xFF1976D2));
    expect(effective.textColor, const Color(0xFFFFF9C4));
  });

  test('an immediate setting update waits for persisted settings to load',
      () async {
    SharedPreferences.setMockInitialValues({
      'overlay_show_datetime': false,
      'overlay_watermark_text': 'Persisted brand',
    });
    final notifier = OverlaySettingsNotifier();
    addTearDown(notifier.dispose);

    await notifier.setShowAltitude(false);

    expect(notifier.state.showDateTime, isFalse);
    expect(notifier.state.showAltitude, isFalse);
    expect(notifier.state.watermarkText, 'Persisted brand');
  });
}
