import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppExitInfo {
  final int reason;
  final String reasonName;
  final int timestampMs;
  final int importance;
  final String description;

  const AppExitInfo({
    required this.reason,
    required this.reasonName,
    required this.timestampMs,
    required this.importance,
    required this.description,
  });

  factory AppExitInfo.fromMap(Map<Object?, Object?> map) {
    return AppExitInfo(
      reason: map['reason'] as int? ?? 0,
      reasonName: map['reasonName'] as String? ?? 'unknown',
      timestampMs: map['timestampMs'] as int? ?? 0,
      importance: map['importance'] as int? ?? 0,
      description: map['description'] as String? ?? '',
    );
  }

  bool get wasUserRequestedStop {
    return reasonName == 'user_requested' || reasonName == 'user_stopped';
  }

  Map<String, Object?> toDiagnostics() {
    return {
      'exitReason': reason,
      'exitReasonName': reasonName,
      'exitTimestampMs': timestampMs,
      'exitImportance': importance,
      'exitDescription': description,
    };
  }
}

class AppExitInfoService {
  static const MethodChannel _channel =
      MethodChannel('surveycam/local_environment');

  const AppExitInfoService._();

  static Future<AppExitInfo?> getLastExitInfo() async {
    if (kIsWeb || !Platform.isAndroid) return null;

    try {
      final result = await _channel.invokeMethod<Object?>(
        'getLastAppExitInfo',
      );
      if (result is Map) {
        return AppExitInfo.fromMap(result);
      }
    } catch (error) {
      debugPrint('Last app exit info unavailable: $error');
    }
    return null;
  }
}
