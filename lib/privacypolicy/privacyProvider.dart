import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

final privacyProvider = StateNotifierProvider<PrivacyNotifier, bool?>((ref) {
  return PrivacyNotifier();
});

class PrivacyNotifier extends StateNotifier<bool?> {
  static const int currentPolicyVersion = 2;

  PrivacyNotifier() : super(null) {
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final accepted = prefs.getBool('privacyAccepted') ?? false;
      final acceptedVersion = prefs.getInt('privacyPolicyVersion') ?? 0;

      if (mounted) {
        state = accepted && acceptedVersion == currentPolicyVersion;
      }
    } catch (e) {
      if (mounted) {
        state = false;
      }
    }
  }

  Future<void> acceptPolicy() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('privacyAccepted', true);
      await prefs.setInt('privacyPolicyVersion', currentPolicyVersion);

      if (mounted) {
        state = true;
      }
    } catch (e) {
      if (mounted) {
        state = false;
      }
    }
  }

  Future<void> resetPolicy() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.remove('privacyAccepted');
      await prefs.remove('privacyPolicyVersion');

      if (mounted) {
        state = false;
      }
    } catch (e) {
      if (mounted) {
        state = false;
      }
    }
  }
}
