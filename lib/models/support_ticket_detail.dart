import 'support_ticket.dart';

class TicketEvidenceItem {
  const TicketEvidenceItem({
    required this.id,
    required this.type,
    required this.fileName,
    required this.contentType,
    required this.fileSize,
    this.uploadedByUserId,
    this.uploadedByName,
  });

  final String id;
  final String type;
  final String fileName;
  final String contentType;
  final int fileSize;
  final String? uploadedByUserId;
  final String? uploadedByName;

  factory TicketEvidenceItem.fromJson(Map<String, dynamic> json) =>
      TicketEvidenceItem(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? 'DOCUMENT',
        fileName: json['originalFileName'] as String? ?? 'Evidence',
        contentType:
            json['contentType'] as String? ?? 'application/octet-stream',
        fileSize: json['fileSize'] as int? ?? 0,
        uploadedByUserId: json['uploadedByUserId'] as String?,
        uploadedByName: json['uploadedByName'] as String?,
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
    this.advanced,
  });

  final SupportTicket ticket;
  final String openedByName;
  final String openedByEmail;
  final String? tripId;
  final String? reservationId;
  final String? reportedUserId;
  final num? priorityScore;
  final AdvancedSupportDetails? advanced;
  final List<TicketEvidenceItem> evidence;
  final List<TicketStatementItem> statements;
  final List<TicketDecisionItem> decisions;
  final List<TicketHistoryItem> history;
  final List<TicketContestationItem> contestations;

  factory AdminSupportTicketDetails.fromJson(
    Map<String, dynamic> json, [
    Map<String, dynamic>? advancedJson,
  ]) {
    final ticketJson = json['ticket'] as Map<String, dynamic>? ?? const {};
    return AdminSupportTicketDetails(
      ticket: SupportTicket.fromJson(ticketJson),
      openedByName: ticketJson['userName'] as String? ?? 'Deleted user',
      openedByEmail: ticketJson['userEmail'] as String? ?? '',
      tripId: ticketJson['tripId'] as String?,
      reservationId: ticketJson['reservationId'] as String?,
      reportedUserId: ticketJson['reportedUserId'] as String?,
      priorityScore: ticketJson['priorityScore'] as num?,
      advanced: advancedJson == null
          ? null
          : AdvancedSupportDetails.fromJson(advancedJson),
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

class TicketRiskSignalItem {
  const TicketRiskSignalItem({
    required this.term,
    required this.excerpt,
    required this.negated,
  });
  final String term;
  final String excerpt;
  final bool negated;
  factory TicketRiskSignalItem.fromJson(Map<String, dynamic> json) =>
      TicketRiskSignalItem(
        term: json['term'] as String? ?? '',
        excerpt: json['excerpt'] as String? ?? '',
        negated: json['negated'] as bool? ?? false,
      );
}

class TicketAnalysisItem {
  const TicketAnalysisItem({
    required this.score,
    required this.severity,
    required this.reportCount,
    required this.previousInfractions,
    required this.waitingHours,
    required this.slaState,
    required this.remainingMinutes,
    required this.riskSignals,
  });
  final num score;
  final int severity;
  final int reportCount;
  final int previousInfractions;
  final num waitingHours;
  final String slaState;
  final int remainingMinutes;
  final List<TicketRiskSignalItem> riskSignals;
  factory TicketAnalysisItem.fromJson(Map<String, dynamic> json) =>
      TicketAnalysisItem(
        score: json['score'] as num? ?? 0,
        severity: (json['severity'] as num?)?.toInt() ?? 0,
        reportCount: (json['reportCount'] as num?)?.toInt() ?? 0,
        previousInfractions:
            (json['previousInfractions'] as num?)?.toInt() ?? 0,
        waitingHours: json['waitingHours'] as num? ?? 0,
        slaState: json['slaState'] as String? ?? 'ON_TIME',
        remainingMinutes: (json['remainingMinutes'] as num?)?.toInt() ?? 0,
        riskSignals: AdminSupportTicketDetails._rows(json['riskSignals'])
            .map(TicketRiskSignalItem.fromJson)
            .toList(growable: false),
      );
}

class TicketEscalationItem {
  const TicketEscalationItem({
    required this.type,
    required this.message,
    this.createdAt,
  });
  final String type;
  final String message;
  final DateTime? createdAt;
  factory TicketEscalationItem.fromJson(Map<String, dynamic> json) =>
      TicketEscalationItem(
        type: json['type'] as String? ?? '',
        message: json['message'] as String? ?? '',
        createdAt: DateTime.tryParse('${json['createdAt']}')?.toLocal(),
      );
}

class TicketAssignmentItem {
  const TicketAssignmentItem({
    required this.id,
    required this.agentName,
    required this.algorithm,
    required this.status,
    required this.explanation,
  });
  final String id;
  final String agentName;
  final String algorithm;
  final String status;
  final String explanation;
  factory TicketAssignmentItem.fromJson(Map<String, dynamic> json) =>
      TicketAssignmentItem(
        id: json['id'] as String? ?? '',
        agentName: json['agentName'] as String? ?? 'Agent',
        algorithm: json['algorithm'] as String? ?? '',
        status: json['status'] as String? ?? '',
        explanation: json['explanation'] as String? ?? '',
      );
}

class TicketEvidenceAnalysisItem {
  const TicketEvidenceAnalysisItem({
    required this.evidenceId,
    required this.status,
    required this.sha256,
    this.detectedType,
    this.duplicateEvidenceId,
    this.extractedText,
    this.errorMessage,
  });
  final String evidenceId;
  final String status;
  final String sha256;
  final String? detectedType;
  final String? duplicateEvidenceId;
  final String? extractedText;
  final String? errorMessage;

  bool get isComplete => status == 'COMPLETE';
  bool get isPartial => status == 'PARTIAL';

  factory TicketEvidenceAnalysisItem.fromJson(Map<String, dynamic> json) =>
      TicketEvidenceAnalysisItem(
        evidenceId: json['evidenceId'] as String? ?? '',
        status: json['status'] as String? ?? '',
        sha256: json['sha256'] as String? ?? '',
        detectedType: json['detectedType'] as String?,
        duplicateEvidenceId: json['duplicateEvidenceId'] as String?,
        extractedText: json['extractedText'] as String?,
        errorMessage: json['errorMessage'] as String?,
      );
}

class TicketWeatherItem {
  const TicketWeatherItem({
    required this.status,
    required this.source,
    this.temperatureC,
    this.precipitationMm,
    this.windSpeedKmh,
    this.weatherCode,
    this.errorMessage,
  });
  final String status;
  final String source;
  final num? temperatureC;
  final num? precipitationMm;
  final num? windSpeedKmh;
  final int? weatherCode;
  final String? errorMessage;
  factory TicketWeatherItem.fromJson(Map<String, dynamic> json) =>
      TicketWeatherItem(
        status: json['status'] as String? ?? '',
        source: json['source'] as String? ?? 'Open-Meteo',
        temperatureC: json['temperatureC'] as num?,
        precipitationMm: json['precipitationMm'] as num?,
        windSpeedKmh: json['windSpeedKmh'] as num?,
        weatherCode: (json['weatherCode'] as num?)?.toInt(),
        errorMessage: json['errorMessage'] as String?,
      );
}

class TicketGeoItem {
  const TicketGeoItem({
    required this.status,
    required this.plannedLat,
    required this.plannedLng,
    required this.source,
    this.destinationLat,
    this.destinationLng,
    this.actualLat,
    this.actualLng,
    this.nearbyPlaces,
    this.idealDistanceM,
    this.idealDurationS,
    this.actualDistanceM,
    this.routePolyline,
    this.routeVerdict,
    this.routeError,
    this.actualPoints = const [],
    this.errorMessage,
  });
  final String status;
  final num plannedLat;
  final num plannedLng;
  final num? destinationLat;
  final num? destinationLng;
  final num? actualLat;
  final num? actualLng;
  final String? nearbyPlaces;
  final int? idealDistanceM;
  final int? idealDurationS;
  final int? actualDistanceM;
  final String? routePolyline;
  final String? routeVerdict;
  final String? routeError;
  final List<TicketGeoPoint> actualPoints;
  final String source;
  final String? errorMessage;
  factory TicketGeoItem.fromJson(Map<String, dynamic> json) => TicketGeoItem(
    status: json['status'] as String? ?? '',
    plannedLat: json['plannedLat'] as num? ?? 0,
    plannedLng: json['plannedLng'] as num? ?? 0,
    destinationLat: json['destinationLat'] as num?,
    destinationLng: json['destinationLng'] as num?,
    actualLat: json['actualLat'] as num?,
    actualLng: json['actualLng'] as num?,
    nearbyPlaces: json['nearbyPlaces'] as String?,
    idealDistanceM: (json['idealDistanceM'] as num?)?.round(),
    idealDurationS: (json['idealDurationS'] as num?)?.round(),
    actualDistanceM: (json['actualDistanceM'] as num?)?.round(),
    routePolyline: json['routePolyline'] as String?,
    routeVerdict: json['routeVerdict'] as String?,
    routeError: json['routeError'] as String?,
    actualPoints: AdminSupportTicketDetails._rows(json['actualPoints'])
        .map(TicketGeoPoint.fromJson)
        .toList(growable: false),
    source: json['source'] as String? ?? 'OpenStreetMap contributors',
    errorMessage: json['errorMessage'] as String?,
  );
}

class TicketGeoPoint {
  const TicketGeoPoint({required this.lat, required this.lng});

  final num lat;
  final num lng;

  factory TicketGeoPoint.fromJson(Map<String, dynamic> json) => TicketGeoPoint(
    lat: json['lat'] as num? ?? 0,
    lng: json['lng'] as num? ?? 0,
  );
}

class AdvancedSupportDetails {
  const AdvancedSupportDetails({
    required this.analysis,
    required this.escalations,
    required this.assignments,
    required this.evidenceAnalyses,
    this.weather,
    this.geo,
    this.assignedAgentName,
  });
  final TicketAnalysisItem analysis;
  final List<TicketEscalationItem> escalations;
  final List<TicketAssignmentItem> assignments;
  final List<TicketEvidenceAnalysisItem> evidenceAnalyses;
  final TicketWeatherItem? weather;
  final TicketGeoItem? geo;
  final String? assignedAgentName;
  factory AdvancedSupportDetails.fromJson(
    Map<String, dynamic> json,
  ) => AdvancedSupportDetails(
    analysis: TicketAnalysisItem.fromJson(
      json['analysis'] as Map<String, dynamic>? ?? const {},
    ),
    escalations: AdminSupportTicketDetails._rows(json['escalations'])
        .map(TicketEscalationItem.fromJson)
        .toList(growable: false),
    assignments: AdminSupportTicketDetails._rows(json['assignments'])
        .map(TicketAssignmentItem.fromJson)
        .toList(growable: false),
    evidenceAnalyses: AdminSupportTicketDetails._rows(json['evidenceAnalyses'])
        .map(TicketEvidenceAnalysisItem.fromJson)
        .toList(growable: false),
    weather: json['weather'] is Map<String, dynamic>
        ? TicketWeatherItem.fromJson(json['weather'] as Map<String, dynamic>)
        : null,
    geo: json['geo'] is Map<String, dynamic>
        ? TicketGeoItem.fromJson(json['geo'] as Map<String, dynamic>)
        : null,
    assignedAgentName: json['assignedAgentName'] as String?,
  );
}
