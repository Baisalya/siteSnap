import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/core/monetization/entitlement_storage.dart';

void main() {
  final verifiedAt = DateTime.utc(2026, 8, 8, 12);
  const grace = Duration(days: 7);

  test('fresh active entitlement is usable during offline grace', () {
    final entitlement = CachedEntitlement(
      isActive: true,
      verifiedAt: verifiedAt,
      expiresAt: verifiedAt.add(const Duration(days: 365)),
    );

    expect(
      entitlement.isUsableAt(
        verifiedAt.add(const Duration(days: 6)),
        grace,
      ),
      isTrue,
    );
  });

  test('expired or stale entitlement cannot unlock Pro', () {
    final expired = CachedEntitlement(
      isActive: true,
      verifiedAt: verifiedAt,
      expiresAt: verifiedAt.add(const Duration(days: 1)),
    );
    final stale = CachedEntitlement(isActive: true, verifiedAt: verifiedAt);

    expect(
      expired.isUsableAt(verifiedAt.add(const Duration(days: 2)), grace),
      isFalse,
    );
    expect(
      stale.isUsableAt(verifiedAt.add(const Duration(days: 8)), grace),
      isFalse,
    );
  });

  test('clock rollback cannot extend a cached entitlement', () {
    final entitlement = CachedEntitlement(
      isActive: true,
      verifiedAt: verifiedAt,
    );

    expect(
      entitlement.isUsableAt(
        verifiedAt.subtract(const Duration(minutes: 1)),
        grace,
      ),
      isFalse,
    );
  });
}
