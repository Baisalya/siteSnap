import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'billing_models.dart';
import 'premium_config.dart';

class PurchaseVerificationResult {
  const PurchaseVerificationResult({
    required this.isValid,
    required this.isActive,
    this.isDefinitive = true,
    this.expiresAt,
    this.message,
  });

  final bool isValid;
  final bool isActive;
  final bool isDefinitive;
  final DateTime? expiresAt;
  final String? message;
}

abstract interface class PurchaseVerifier {
  bool get isConfigured;

  String? get configurationMessage;

  Future<PurchaseVerificationResult> verify(StorePurchase purchase);
}

class PlayPurchaseVerifier implements PurchaseVerifier {
  PlayPurchaseVerifier({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  static const String _packageName = 'com.baishalya.surveycam';
  final HttpClient _httpClient;

  Uri? get _verificationUri {
    final uri = Uri.tryParse(PremiumConfig.verificationUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri;
  }

  bool get _localVerificationAllowed =>
      !kReleaseMode || PremiumConfig.allowLocalPlayVerification;

  @override
  bool get isConfigured =>
      _verificationUri != null || _localVerificationAllowed;

  @override
  String? get configurationMessage => isConfigured
      ? null
      : 'Secure Play purchase verification is not configured.';

  @override
  Future<PurchaseVerificationResult> verify(StorePurchase purchase) async {
    if (purchase.productId != PremiumConfig.proProductId) {
      return const PurchaseVerificationResult(
        isValid: false,
        isActive: false,
        message: 'The purchase belongs to an unknown product.',
      );
    }
    if (purchase.serverVerificationData.trim().isEmpty) {
      return const PurchaseVerificationResult(
        isValid: false,
        isActive: false,
        message: 'Google Play did not return a purchase token.',
      );
    }

    final uri = _verificationUri;
    if (uri == null) {
      if (!_localVerificationAllowed) {
        return PurchaseVerificationResult(
          isValid: false,
          isActive: false,
          isDefinitive: false,
          message: configurationMessage,
        );
      }

      // License-test/debug fallback only. Production builds should verify the
      // token through the Play Developer API on a trusted server.
      return const PurchaseVerificationResult(
        isValid: true,
        isActive: true,
        message: 'Locally accepted for Play license testing.',
      );
    }

    try {
      final request = await _httpClient.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(jsonEncode({
        'packageName': _packageName,
        'productId': purchase.productId,
        'purchaseToken': purchase.serverVerificationData,
        'purchaseId': purchase.purchaseId,
      }));

      final response =
          await request.close().timeout(const Duration(seconds: 12));
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return PurchaseVerificationResult(
          isValid: false,
          isActive: false,
          isDefinitive: false,
          message: 'Verification server returned ${response.statusCode}.',
        );
      }

      final json = jsonDecode(body);
      if (json is! Map) {
        throw const FormatException('Verification response is not an object.');
      }
      final expiresAtMs = (json['expiresAtMs'] as num?)?.toInt();
      return PurchaseVerificationResult(
        isValid: json['valid'] == true,
        isActive: json['active'] == true,
        expiresAt: expiresAtMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(expiresAtMs, isUtc: true),
        message: json['message'] as String?,
      );
    } catch (error) {
      return PurchaseVerificationResult(
        isValid: false,
        isActive: false,
        isDefinitive: false,
        message: 'Could not verify the purchase: $error',
      );
    }
  }
}
