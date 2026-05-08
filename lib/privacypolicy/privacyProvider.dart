import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final privacyProvider =
StateNotifierProvider<PrivacyNotifier, bool>((ref) {
  return PrivacyNotifier();
});

class PrivacyNotifier extends StateNotifier<bool> {
  PrivacyNotifier() : super(false) {
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final accepted = prefs.getBool('privacyAccepted') ?? false;

      state = accepted;
    } catch (e) {
      state = false;
    }
  }

  Future<void> acceptPolicy() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('privacyAccepted', true);

      state = true;
    } catch (e) {
      state = false;
    }
  }

  Future<void> resetPolicy() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.remove('privacyAccepted');

      state = false;
    } catch (e) {
      state = false;
    }
  }
}