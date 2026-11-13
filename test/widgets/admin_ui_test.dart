import 'package:carshare/widgets/admin_ui.dart';
import 'package:carshare/widgets/notification_filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('helpers', () {
    test('dates read like dates', () {
      expect(adminDate('2026-11-13T10:00:00Z'), '13 Nov 2026');
      expect(adminDate(null), 'Not provided');
      expect(adminDate('nonsense'), 'nonsense');
      expect(adminDate(null, fallback: '—'), '—');
    });

    test('enum codes become sentences', () {
      expect(humanize('BEHAVIOUR_ISSUE'), 'Behaviour issue');
      expect(humanize('under_review'), 'Under review');
      expect(humanize(null), 'Unknown');
    });

    test('priority and SLA are named, not numbered', () {
      expect(priorityState(70).label, 'Urgent');
      expect(priorityState(48).label, 'High');
      expect(priorityState(26).label, 'Medium');
      expect(priorityState(3).label, 'Normal');
      final now = DateTime(2026, 11, 13, 12);
      expect(
        slaState(DateTime(2026, 11, 16, 12).toIso8601String(), now: now).label,
        'Due in 3 days',
      );
      expect(
        slaState(DateTime(2026, 11, 13, 20).toIso8601String(), now: now).label,
        'Due today',
      );
      expect(
        slaState(DateTime(2026, 11, 11, 12).toIso8601String(), now: now).label,
        'Overdue by 2 days',
      );
      expect(slaState(null).label, 'No deadline');
    });
  });

  // The new building blocks must not overflow on a 320 x 568 phone, with long text. (The test
  // font is much wider than the app's, so the pill text is kept short here.)
  testWidgets('admin widgets fit a small screen', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const long =
        'A very long line of secondary information that has to wrap or be cut '
        'short rather than overflow the card it sits in';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        AdminIconBadge(Icons.route_outlined),
                        SizedBox(width: 12),
                        Expanded(child: Text(long)),
                        AdminPill('Late', colour: Colors.red),
                      ],
                    ),
                    const AdminInfoLine(Icons.mail_outline, long),
                    const AdminFact('Reported user id', long),
                    AdminDecisionBar(onApprove: () {}, onReject: () {}),
                  ],
                ),
              ),
              const AdminBlock(
                title: 'Evidence (2)',
                icon: Icons.attach_file_rounded,
                child: Text(long),
              ),
              NotificationFilterBar(
                summary: '12 unread of 30 updates',
                showUnreadOnly: false,
                onChanged: (_) {},
              ),
              const AdminCollapsible(
                title: 'Show details',
                children: [Text(long)],
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Approve'), findsOneWidget);
  });
}
