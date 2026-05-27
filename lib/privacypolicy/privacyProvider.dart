import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

final privacyProvider =
StateNotifierProvider<PrivacyNotifier, bool?>((ref) {
  return PrivacyNotifier();
});

class PrivacyNotifier extends StateNotifier<bool?> {
  PrivacyNotifier() : super(null) {
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final accepted = prefs.getBool('privacyAccepted') ?? false;

      if (mounted) {
        state = accepted;
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