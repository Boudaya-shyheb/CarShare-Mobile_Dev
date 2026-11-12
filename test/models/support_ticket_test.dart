import 'package:carshare/models/support_notification.dart';
import 'package:carshare/models/support_report_target.dart';
import 'package:carshare/models/support_ticket.dart';
import 'package:carshare/models/support_ticket_detail.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the backend reference, deadline and status', () {
    final ticket = SupportTicket.fromJson({
      'id': 'ticket-1',
      'reference': 'DSP-2026-ABC12345',
      'category': 'Driver was late',
      'title': 'Driver was late',
      'description': 'The driver arrived late.',
      'status': 'CLOSED',
      'reportedUserId': 'driver-1',
      'reportedUserName': 'Driver One',
      'reportedUserRole': 'DRIVER',
      'tripId': 'trip-1',
      'tripLabel': 'Tunis → Sousse',
      'deadline': '2026-11-13T10:00:00Z',
      'createdAt': '2026-11-12T10:00:00Z',
    });

    expect(ticket.reference, 'DSP-2026-ABC12345');
    expect(ticket.status, TicketStatus.closed);
    expect(ticket.isResolved, isTrue);
    expect(ticket.deadline, isNotNull);
    expect(ticket.reportedUserName, 'Driver One');
    expect(ticket.reportedUserRole, 'DRIVER');
    expect(ticket.trip, 'Tunis → Sousse');
  });

  test('parses evidence, statements, decisions and history', () {
    final evidence = TicketEvidenceItem.fromJson({
      'id': 'evidence-1',
      'type': 'PHOTO',
      'originalFileName': 'proof.jpg',
      'contentType': 'image/jpeg',
      'fileSize': 1200,
      'uploadedByName': 'Driver One',
    });
    final statement = TicketStatementItem.fromJson({
      'id': 'statement-1',
      'authorName': 'Passenger',
      'text': 'The driver arrived late.',
    });
    final decision = TicketDecisionItem.fromJson({
      'result': 'CONFIRMED',
      'reason': 'GPS evidence confirmed the delay.',
      'penaltyPoints': 2,
      'decisionNumber': 1,
      'finalDecision': false,
    });
    final history = TicketHistoryItem.fromJson({
      'fromStatus': 'UNDER_REVIEW',
      'toStatus': 'RESOLVED',
      'createdAt': '2026-11-12T10:00:00Z',
    });

    expect(evidence.fileName, 'proof.jpg');
    expect(evidence.uploadedByName, 'Driver One');
    expect(statement.authorName, 'Passenger');
    expect(decision.penaltyPoints, 2);
    expect(history.toStatus, 'RESOLVED');
  });

  test('parses report target and unread support notification', () {
    final target = SupportReportTarget.fromJson({
      'userId': 'passenger-1',
      'fullName': 'Passenger One',
      'reservationId': 'reservation-1',
      'role': 'PASSENGER',
    });
    final notification = SupportNotificationItem.fromJson({
      'id': 'notification-1',
      'ticketId': 'ticket-1',
      'ticketReference': 'DSP-2026-ABC12345',
      'type': 'RESPONSE_REQUESTED',
      'title': 'Your response is requested',
      'message': 'Add your statement and evidence.',
      'createdAt': '2026-11-12T10:00:00Z',
      'read': false,
    });

    expect(target.reservationId, 'reservation-1');
    expect(target.role, 'PASSENGER');
    expect(notification.ticketReference, 'DSP-2026-ABC12345');
    expect(notification.read, isFalse);
  });

  test('parses the complete admin ticket case', () {
    final details = AdminSupportTicketDetails.fromJson({
      'ticket': {
        'id': 'ticket-1',
        'reference': 'DSP-2026-ABC12345',
        'category': 'Other',
        'title': 'Damaged vehicle',
        'description': 'A mirror was damaged during the trip.',
        'status': 'UNDER_REVIEW',
        'priorityScore': 8.5,
        'userName': 'Passenger One',
        'userEmail': 'passenger@example.com',
        'tripId': 'trip-1',
        'createdAt': '2026-11-12T10:00:00Z',
      },
      'evidence': [
        {
          'id': 'evidence-1',
          'type': 'PHOTO',
          'originalFileName': 'mirror.jpg',
          'contentType': 'image/jpeg',
          'fileSize': 2048,
        },
      ],
      'statements': [],
      'decisions': [],
      'history': [],
      'contestations': [
        {
          'id': 'contestation-1',
          'reason': 'The decision did not consider the photo.',
          'contestedByName': 'Passenger One',
        },
      ],
    });

    expect(details.ticket.reference, 'DSP-2026-ABC12345');
    expect(details.openedByEmail, 'passenger@example.com');
    expect(details.priorityScore, 8.5);
    expect(details.evidence.single.fileName, 'mirror.jpg');
    expect(details.contestations.single.userName, 'Passenger One');
  });
}
