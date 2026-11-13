import 'package:carshare/models/support_ticket_detail.dart';
import 'package:carshare/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

UserProfile profile(String status, DateTime? until) => UserProfile.fromJson({
  'id': 'u1',
  'fullName': 'Mariem',
  'phone': '+21622222222',
  'email': 'm@carshare.tn',
  'role': 'passenger',
  'createdAt': '2026-11-01T10:00:00Z',
  'status': status,
  'statusUntil': until?.toUtc().toIso8601String(),
});

void main() {
  test('a suspension whose end date has passed reads as active', () {
    final user = profile(
      'SUSPENDED',
      DateTime.now().subtract(const Duration(minutes: 5)),
    );

    expect(user.effectiveStatus, 'ACTIVE');
    expect(user.effectiveStatusUntil, isNull);
  });

  test('a suspension still running keeps its status and date', () {
    final until = DateTime.now().add(const Duration(days: 1));
    final user = profile('SUSPENDED', until);

    expect(user.effectiveStatus, 'SUSPENDED');
    expect(user.effectiveStatusUntil, isNotNull);
  });

  test('a ban never reads as active, and an open warning stays a warning', () {
    expect(
      profile(
        'BANNED',
        DateTime.now().subtract(const Duration(days: 3)),
      ).effectiveStatus,
      'BANNED',
    );
    expect(profile('WARNING', null).effectiveStatus, 'WARNING');
  });

  test('an evidence analysis says whether it is complete or partial', () {
    final partial = TicketEvidenceAnalysisItem.fromJson({
      'evidenceId': 'e1',
      'status': 'PARTIAL',
      'sha256': 'abc',
      'errorMessage': 'Apache Tika is unavailable.',
    });
    final complete = TicketEvidenceAnalysisItem.fromJson({
      'evidenceId': 'e1',
      'status': 'COMPLETE',
      'sha256': 'abc',
      'extractedText': 'hello',
    });

    expect(partial.isPartial, isTrue);
    expect(partial.isComplete, isFalse);
    expect(partial.errorMessage, contains('Tika'));
    expect(complete.isComplete, isTrue);
    expect(complete.extractedText, 'hello');
  });
}
