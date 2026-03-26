import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
final privacyProvider =
StateNotifierProvider<PrivacyNotifier, bool?>((ref) {
  return PrivacyNotifier();
});

class PrivacyNotifier extends StateNotifier<bool?> {
  PrivacyNotifier() : super(null) {
    loadStatus();
  }

  Future<void> loadStatus() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('privacyAccepted') ?? false;
  }

  Future<void> acceptPolicy() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacyAccepted', true);
    state = true;
  }
}