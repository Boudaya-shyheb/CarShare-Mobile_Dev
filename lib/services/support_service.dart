import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/support_category.dart';
import '../models/support_notification.dart';
import '../models/support_report_target.dart';
import '../models/support_ticket.dart';
import '../models/support_ticket_detail.dart';
import 'api_client.dart';
import 'support_local_database.dart';

class SupportService {
  SupportService._();

  static final SupportService instance = SupportService._();
  final ApiClient _api = ApiClient.instance;
  final SupportLocalDatabase _local = SupportLocalDatabase.instance;

  Future<List<SupportTicket>> tickets(String userId) async {
    try {
      final rows = await _api.getList('/support/tickets');
      await _local.cacheTickets(userId, rows);
      return rows.map(SupportTicket.fromJson).toList(growable: false);
    } catch (_) {
      final cached = await _local.cachedTickets(userId);
      if (cached.isEmpty) rethrow;
      return cached.map(SupportTicket.fromJson).toList(growable: false);
    }
  }

  Future<List<SupportCategory>> categories() async {
    try {
      final rows = await _api.getList('/support/categories');
      await _local.cacheCategories(rows);
      return rows.map(SupportCategory.fromJson).toList(growable: false);
    } catch (_) {
      final cached = await _local.cachedCategories();
      if (cached.isEmpty) rethrow;
      return cached.map(SupportCategory.fromJson).toList(growable: false);
    }
  }

  Future<List<SupportReportTarget>> reportTargets(String tripId) async =>
      (await _api.getList('/support/tickets/report-targets?tripId=$tripId'))
          .map(SupportReportTarget.fromJson)
          .toList(growable: false);

  Future<List<SupportNotificationItem>> notifications() async =>
      (await _api.getList('/support/notifications'))
          .map(SupportNotificationItem.fromJson)
          .toList(growable: false);

  Future<int> unreadNotificationCount() async {
    final row = await _api.get('/support/notifications/unread-count');
    return (row['count'] as num?)?.toInt() ?? 0;
  }

  Future<void> markNotificationRead(String notificationId) async {
    await _api.put('/support/notifications/$notificationId/read', const {});
  }

  Future<SupportTicket> createTicket({
    required String categoryId,
    required String category,
    required String title,
    required String description,
    String? tripId,
    String? reservationId,
  }) async {
    final body = <String, dynamic>{
      'categoryId': categoryId,
      'category': category,
      'title': title,
      'description': description,
    };
    if (tripId != null) body['tripId'] = tripId;
    if (reservationId != null) body['reservationId'] = reservationId;
    return SupportTicket.fromJson(await _api.post('/support/tickets', body));
  }

  Future<SupportTicketDetails> ticketDetails(String ticketId) async {
    final results = await Future.wait<List<Map<String, dynamic>>>([
      _api.getList('/support/tickets/$ticketId/evidence'),
      _api.getList('/support/tickets/$ticketId/statements'),
      _api.getList('/support/tickets/$ticketId/decisions'),
      _api.getList('/support/tickets/$ticketId/history'),
    ]);
    return SupportTicketDetails(
      evidence: results[0]
          .map(TicketEvidenceItem.fromJson)
          .toList(growable: false),
      statements: results[1]
          .map(TicketStatementItem.fromJson)
          .toList(growable: false),
      decisions: results[2]
          .map(TicketDecisionItem.fromJson)
          .toList(growable: false),
      history: results[3]
          .map(TicketHistoryItem.fromJson)
          .toList(growable: false),
    );
  }

  Future<void> addStatement(String ticketId, String text) async {
    await _api.post('/support/tickets/$ticketId/statements', {'text': text});
  }

  Future<void> contest(String ticketId, String reason) async {
    await _api.post('/support/tickets/$ticketId/contestations', {
      'reason': reason,
    });
  }

  Future<void> deleteEvidence(String ticketId, String evidenceId) async {
    await _api.delete('/support/tickets/$ticketId/evidence/$evidenceId');
  }

  Future<Uint8List> evidenceBytes(String ticketId, String evidenceId) =>
      _api.getBytes('/support/tickets/$ticketId/evidence/$evidenceId/file');

  Future<AdminSupportTicketDetails> adminTicketDetails(String ticketId) async {
    final rows = await Future.wait([
      _api.get('/admin/support/tickets/$ticketId'),
      _api.get('/admin/support/tickets/$ticketId/advanced'),
    ]);
    return AdminSupportTicketDetails.fromJson(rows[0], rows[1]);
  }

  Future<void> refreshAdminAnalysis(String ticketId) async {
    await _api.post(
      '/admin/support/tickets/$ticketId/analysis/refresh',
      const {},
    );
  }

  Future<void> proposeAssignment(String ticketId) async {
    await _api.post(
      '/admin/support/tickets/$ticketId/assignments/propose',
      const {},
    );
  }

  Future<void> confirmAssignment(String ticketId, String proposalId) async {
    await _api.post(
      '/admin/support/tickets/$ticketId/assignments/$proposalId/confirm',
      const {},
    );
  }

  Future<void> analyzeEvidence(String ticketId, String evidenceId) async {
    await _api.post(
      '/admin/support/tickets/$ticketId/evidence/$evidenceId/analyze',
      const {},
    );
  }

  Future<void> refreshWeather(String ticketId) async {
    await _api.post(
      '/admin/support/tickets/$ticketId/weather/refresh',
      const {},
    );
  }

  Future<void> refreshGeo(String ticketId) async {
    await _api.post('/admin/support/tickets/$ticketId/geo/refresh', const {});
  }

  Future<Uint8List> adminEvidenceBytes(String ticketId, String evidenceId) =>
      _api.getBytes(
        '/admin/support/tickets/$ticketId/evidence/$evidenceId/file',
      );

  Future<void> changeAdminStatus({
    required String ticketId,
    required String status,
    required String reason,
  }) async {
    await _api.put('/admin/support/tickets/$ticketId/status', {
      'status': status,
      'reason': reason,
    });
  }

  Future<void> createAdminDecision({
    required String ticketId,
    required String result,
    required String reason,
    required int penaltyPoints,
  }) async {
    await _api.post('/admin/support/tickets/$ticketId/decisions', {
      'result': result,
      'reason': reason,
      'penaltyPoints': penaltyPoints,
    });
  }

  Future<void> uploadEvidence({
    required String ticketId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String type,
  }) async {
    final token = await _api.readToken();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiClient.baseUrl}/support/tickets/$ticketId/evidence'),
    );
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.fields['type'] = type;
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
        contentType: MediaType.parse(mimeType),
      ),
    );
    try {
      final streamed = await request.send().timeout(
        const Duration(seconds: 20),
      );
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          _problemDetail(response.body, 'The evidence could not be uploaded.'),
          statusCode: response.statusCode,
        );
      }
    } on ApiException {
      rethrow;
    } on SocketException {
      throw const ApiException(
        'Connection problem. Check the backend and try again.',
      );
    } on TimeoutException {
      throw const ApiException(
        'The evidence upload timed out. Please try again.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Connection problem. Check the backend and try again.',
      );
    }
  }

  Future<void> saveDraft({
    required String userId,
    required String categoryName,
    required String title,
    required String description,
    String? tripId,
    String? reservationId,
    String? categoryId,
  }) => _local.saveDraft(
    userId: userId,
    tripId: tripId,
    reservationId: reservationId,
    categoryId: categoryId,
    categoryName: categoryName,
    title: title,
    description: description,
  );

  Future<Map<String, Object?>?> draft(String userId) => _local.draft(userId);
  Future<void> clearDraft(String userId) => _local.clearDraft(userId);

  String _problemDetail(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded['detail'] as String? ?? fallback;
      }
    } on FormatException {
      // The backend may return an empty or non-JSON body for transport errors.
    }
    return fallback;
  }
}
