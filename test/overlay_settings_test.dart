import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/features/overlay/domain/overlay_settings.dart';

void main() {
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
}
