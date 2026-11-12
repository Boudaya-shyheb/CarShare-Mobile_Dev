import 'support_ticket.dart';

class TicketEvidenceItem {
  const TicketEvidenceItem({
    required this.id,
    required this.type,
    required this.fileName,
    required this.contentType,
    required this.fileSize,
    this.uploadedByUserId,
  });

  final String id;
  final String type;
  final String fileName;
  final String contentType;
  final int fileSize;
  final String? uploadedByUserId;

  factory TicketEvidenceItem.fromJson(Map<String, dynamic> json) =>
      TicketEvidenceItem(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? 'DOCUMENT',
        fileName: json['originalFileName'] as String? ?? 'Evidence',
        contentType:
            json['contentType'] as String? ?? 'application/octet-stream',
        fileSize: json['fileSize'] as int? ?? 0,
        uploadedByUserId: json['uploadedByUserId'] as String?,
      );
}

class TicketStatementItem {
  const TicketStatementItem({
    required this.id,
    required this.authorName,
    required this.text,
    this.authorId,
  });

  final String id;
  final String? authorId;
  final String authorName;
  final String text;

  factory TicketStatementItem.fromJson(Map<String, dynamic> json) =>
      TicketStatementItem(
        id: json['id'] as String? ?? '',
        authorId: json['authorId'] as String?,
        authorName: json['authorName'] as String? ?? 'Deleted user',
        text: json['text'] as String? ?? '',
      );
}

class TicketDecisionItem {
  const TicketDecisionItem({
    required this.result,
    required this.reason,
    required this.penaltyPoints,
    required this.decisionNumber,
    required this.finalDecision,
  });

  final String result;
  final String reason;
  final int penaltyPoints;
  final int decisionNumber;
  final bool finalDecision;

  factory TicketDecisionItem.fromJson(Map<String, dynamic> json) =>
      TicketDecisionItem(
        result: json['result'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        penaltyPoints: json['penaltyPoints'] as int? ?? 0,
        decisionNumber: json['decisionNumber'] as int? ?? 1,
        finalDecision: json['finalDecision'] as bool? ?? false,
      );
}

class TicketHistoryItem {
  const TicketHistoryItem({
    required this.toStatus,
    required this.createdAt,
    this.fromStatus,
    this.reason,
  });

  final String? fromStatus;
  final String toStatus;
  final String? reason;
  final DateTime? createdAt;

  factory TicketHistoryItem.fromJson(Map<String, dynamic> json) =>
      TicketHistoryItem(
        fromStatus: json['fromStatus'] as String?,
        toStatus: json['toStatus'] as String? ?? 'OPEN',
        reason: json['reason'] as String?,
        createdAt: DateTime.tryParse('${json['createdAt']}')?.toLocal(),
      );
}

class SupportTicketDetails {
  const SupportTicketDetails({
    required this.evidence,
    required this.statements,
    required this.decisions,
    required this.history,
  });

  final List<TicketEvidenceItem> evidence;
  final List<TicketStatementItem> statements;
  final List<TicketDecisionItem> decisions;
  final List<TicketHistoryItem> history;
}

class TicketContestationItem {
  const TicketContestationItem({
    required this.userName,
    required this.reason,
    this.createdAt,
  });

  final String userName;
  final String reason;
  final DateTime? createdAt;

  factory TicketContestationItem.fromJson(Map<String, dynamic> json) =>
      TicketContestationItem(
        userName: json['contestedByName'] as String? ?? 'Deleted user',
        reason: json['reason'] as String? ?? '',
        createdAt: DateTime.tryParse('${json['createdAt']}')?.toLocal(),
      );
}

class AdminSupportTicketDetails {
  const AdminSupportTicketDetails({
    required this.ticket,
    required this.openedByName,
    required this.openedByEmail,
    required this.evidence,
    required this.statements,
    required this.decisions,
    required this.history,
    required this.contestations,
    this.tripId,
    this.reservationId,
    this.reportedUserId,
    this.priorityScore,
  });

  final SupportTicket ticket;
  final String openedByName;
  final String openedByEmail;
  final String? tripId;
  final String? reservationId;
  final String? reportedUserId;
  final num? priorityScore;
  final List<TicketEvidenceItem> evidence;
  final List<TicketStatementItem> statements;
  final List<TicketDecisionItem> decisions;
  final List<TicketHistoryItem> history;
  final List<TicketContestationItem> contestations;

  factory AdminSupportTicketDetails.fromJson(Map<String, dynamic> json) {
    final ticketJson = json['ticket'] as Map<String, dynamic>? ?? const {};
    return AdminSupportTicketDetails(
      ticket: SupportTicket.fromJson(ticketJson),
      openedByName: ticketJson['userName'] as String? ?? 'Deleted user',
      openedByEmail: ticketJson['userEmail'] as String? ?? '',
      tripId: ticketJson['tripId'] as String?,
      reservationId: ticketJson['reservationId'] as String?,
      reportedUserId: ticketJson['reportedUserId'] as String?,
      priorityScore: ticketJson['priorityScore'] as num?,
      evidence: _rows(json['evidence'])
          .map(TicketEvidenceItem.fromJson)
          .toList(growable: false),
      statements: _rows(json['statements'])
          .map(TicketStatementItem.fromJson)
          .toList(growable: false),
      decisions: _rows(json['decisions'])
          .map(TicketDecisionItem.fromJson)
          .toList(growable: false),
      history: _rows(json['history'])
          .map(TicketHistoryItem.fromJson)
          .toList(growable: false),
      contestations: _rows(json['contestations'])
          .map(TicketContestationItem.fromJson)
          .toList(growable: false),
    );
  }

  static Iterable<Map<String, dynamic>> _rows(Object? value) =>
      (value as List? ?? const []).whereType<Map<String, dynamic>>();
}
