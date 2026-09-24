import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

enum RewardedAdOutcome { earned, dismissed, unavailable }

class RewardedAdService {
  static const _androidTestRewardedId =
      'ca-app-pub-3940256099942544/5224354917';
  static const _androidReleaseRewardedId = String.fromEnvironment(
    'SURVEYCAM_ADMOB_REWARDED_ID',
    defaultValue: 'ca-app-pub-1529558529658186/7575240208',
  );

  Future<bool>? _initialization;
  RewardedAd? _loadedAd;
  Future<RewardedAd?>? _loadingAd;
  bool _showing = false;
  bool _disposed = false;

  String get _adUnitId =>
      kReleaseMode ? _androidReleaseRewardedId : _androidTestRewardedId;

  Future<RewardedAdOutcome> show() async {
    if (_disposed || !Platform.isAndroid || _showing) {
      return RewardedAdOutcome.unavailable;
    }
    _showing = true;
    try {
      final ready = await (_initialization ??= _initialize());
      if (!ready) _initialization = null;
      if (!ready || _disposed) return RewardedAdOutcome.unavailable;

      final ad = _loadedAd ?? await _loadAd();
      _loadedAd = null;
      if (ad == null || _disposed) return RewardedAdOutcome.unavailable;

      final completion = Completer<RewardedAdOutcome>();
      var earned = false;
      void complete(RewardedAdOutcome outcome) {
        if (!completion.isCompleted) completion.complete(outcome);
      }

      ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          complete(
              earned ? RewardedAdOutcome.earned : RewardedAdOutcome.dismissed);
        },
        onAdFailedToShowFullScreenContent: (ad, _) {
          ad.dispose();
          complete(RewardedAdOutcome.unavailable);
        },
      );
      await ad.show(
        onUserEarnedReward: (_, __) => earned = true,
      );
      return await completion.future;
    } catch (_) {
      return RewardedAdOutcome.unavailable;
    } finally {
      _showing = false;
    }
  }

  Future<bool> _initialize() async {
    final consentUpdated = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(tagForUnderAgeOfConsent: false),
      () async {
        try {
          await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
        } finally {
          if (!consentUpdated.isCompleted) consentUpdated.complete();
        }
      },
      (_) {
        if (!consentUpdated.isCompleted) consentUpdated.complete();
      },
    );

    try {
      await consentUpdated.future.timeout(const Duration(seconds: 15));
    } catch (_) {
      return false;
    }
    if (!await ConsentInformation.instance.canRequestAds()) return false;
    await MobileAds.instance.initialize();
    return true;
  }

  Future<RewardedAd?> _loadAd() async {
    final inFlight = _loadingAd;
    if (inFlight != null) return inFlight;

    final completion = Completer<RewardedAd?>();
    _loadingAd = completion.future;
    try {
      await RewardedAd.load(
        adUnitId: _adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (_disposed) {
              ad.dispose();
              if (!completion.isCompleted) completion.complete(null);
              return;
            }
            _loadedAd = ad;
            if (!completion.isCompleted) completion.complete(ad);
          },
          onAdFailedToLoad: (_) {
            if (!completion.isCompleted) completion.complete(null);
          },
        ),
      );
      return await completion.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => null,
      );
    } catch (_) {
      if (!completion.isCompleted) completion.complete(null);
      return null;
    } finally {
      _loadingAd = null;
    }
  }

  void dispose() {
    _disposed = true;
    _loadedAd?.dispose();
    _loadedAd = null;
  }
}

final rewardedAdServiceProvider = Provider<RewardedAdService>((ref) {
  final service = RewardedAdService();
  ref.onDispose(service.dispose);
  return service;
});
