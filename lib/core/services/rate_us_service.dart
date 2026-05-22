import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/rate_us_dialog.dart';

final ratingServiceProvider = Provider<RatingService>((ref) {
  return const RatingService();
});

class RatingService {
  const RatingService();

  Future<void> init() => RateUsService.init();

  Future<bool> shouldShowDialog() => RateUsService.shouldShowDialog();

  Future<void> markAsRated() => RateUsService.markAsRated();

  Future<void> markAsDontShow() => RateUsService.markAsDontShow();

  Future<void> remindLater() => RateUsService.remindLater();

  Future<void> showRateDialogIfMeetsCriteria(BuildContext context) {
    return RateUsService.showRateDialogIfMeetsCriteria(context);
  }
}

/// Service to handle "Rate Us" logic and persistence.
class RateUsService {
  static const String _keyLastVersion = 'rate_us_last_version';
  static const String _keyLaunchCount = 'rate_us_launch_count';
  static const String _keyFirstLaunchDate = 'rate_us_first_launch_date';
  static const String _keyIsRated = 'rate_us_is_rated';
  static const String _keyDontShowAgain = 'rate_us_dont_show_again';

  static const int _launchThreshold = 3; // Show after 3 launches
  static const int _daysThreshold = 3; // Show after 3 days

  /// Initializes the service, tracks launches, and checks for version updates.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    final lastVersion = prefs.getString(_keyLastVersion);

    // Reset logic if it's a new version
    if (lastVersion != currentVersion) {
      await prefs.setString(_keyLastVersion, currentVersion);
      await prefs.setInt(_keyLaunchCount, 0);
      await prefs.setString(
          _keyFirstLaunchDate, DateTime.now().toIso8601String());
      await prefs.setBool(_keyIsRated, false);
      await prefs.setBool(_keyDontShowAgain, false);
    }

    // Increment launch count
    int launchCount = prefs.getInt(_keyLaunchCount) ?? 0;
    await prefs.setInt(_keyLaunchCount, launchCount + 1);

    // Set first launch date if not exists
    if (prefs.getString(_keyFirstLaunchDate) == null) {
      await prefs.setString(
          _keyFirstLaunchDate, DateTime.now().toIso8601String());
    }
  }

  /// Determines if the dialog should be shown based on criteria.
  static Future<bool> shouldShowDialog() async {
    final prefs = await SharedPreferences.getInstance();

    final bool isRated = prefs.getBool(_keyIsRated) ?? false;
    final bool dontShowAgain = prefs.getBool(_keyDontShowAgain) ?? false;

    if (isRated || dontShowAgain) return false;

    final int launchCount = prefs.getInt(_keyLaunchCount) ?? 0;
    final String? firstLaunchStr = prefs.getString(_keyFirstLaunchDate);

    if (firstLaunchStr == null) return false;

    final DateTime firstLaunchDate = DateTime.parse(firstLaunchStr);
    final int daysSinceFirstLaunch =
        DateTime.now().difference(firstLaunchDate).inDays;

    // Show if launch count OR days threshold met
    return launchCount >= _launchThreshold ||
        daysSinceFirstLaunch >= _daysThreshold;
  }

  /// Marks the app as rated to prevent future prompts for this version.
  static Future<void> markAsRated() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsRated, true);
  }

  /// Marks the app to never show the prompt again for this version.
  static Future<void> markAsDontShow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDontShowAgain, true);
  }

  /// Resets the launch count and date for "Later" option.
  static Future<void> remindLater() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLaunchCount, 0);
    await prefs.setString(
        _keyFirstLaunchDate, DateTime.now().toIso8601String());
  }

  /// Checks criteria and shows the dialog if needed.
  static Future<void> showRateDialogIfMeetsCriteria(
      BuildContext context) async {
    if (await shouldShowDialog()) {
      if (!context.mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const RateUsDialog(),
      );
    }
  }
}
