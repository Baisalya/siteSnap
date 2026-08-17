import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CachedEntitlement {
  const CachedEntitlement({
    required this.isActive,
    required this.verifiedAt,
    this.expiresAt,
  });

  final bool isActive;
  final DateTime verifiedAt;
  final DateTime? expiresAt;

  bool isUsableAt(DateTime now, Duration offlineGrace) {
    if (!isActive) return false;
    if (now.isBefore(verifiedAt)) return false;
    if (expiresAt != null && !now.isBefore(expiresAt!)) return false;
    return now.difference(verifiedAt) <= offlineGrace;
  }

  Map<String, Object?> toJson() => {
        'active': isActive,
        'verifiedAtMs': verifiedAt.millisecondsSinceEpoch,
        'expiresAtMs': expiresAt?.millisecondsSinceEpoch,
      };

  static CachedEntitlement? fromJson(Object? value) {
    if (value is! Map) return null;
    final verifiedAtMs = (value['verifiedAtMs'] as num?)?.toInt();
    if (verifiedAtMs == null) return null;
    final expiresAtMs = (value['expiresAtMs'] as num?)?.toInt();
    return CachedEntitlement(
      isActive: value['active'] == true,
      verifiedAt: DateTime.fromMillisecondsSinceEpoch(verifiedAtMs),
      expiresAt: expiresAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expiresAtMs),
    );
  }
}

abstract interface class EntitlementStorage {
  Future<CachedEntitlement?> load();

  Future<void> save(CachedEntitlement entitlement);

  Future<void> clear();
}

class SharedPreferencesEntitlementStorage implements EntitlementStorage {
  static const _key = 'surveycam_pro_entitlement_v1';

  @override
  Future<CachedEntitlement?> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      final raw = preferences.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      return CachedEntitlement.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(CachedEntitlement entitlement) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(entitlement.toJson()));
  }

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key);
  }
}
