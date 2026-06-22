import 'package:flutter_test/flutter_test.dart';
import 'package:surveycam/core/services/app_exit_info_service.dart';

void main() {
  test('app exit info maps Android user stop diagnostics', () {
    final info = AppExitInfo.fromMap({
      'reason': 10,
      'reasonName': 'user_requested',
      'timestampMs': 12345,
      'importance': 100,
      'description': 'user tapped stop',
    });

    expect(info.wasUserRequestedStop, isTrue);
    expect(info.toDiagnostics(), {
      'exitReason': 10,
      'exitReasonName': 'user_requested',
      'exitTimestampMs': 12345,
      'exitImportance': 100,
      'exitDescription': 'user tapped stop',
    });
  });
}
