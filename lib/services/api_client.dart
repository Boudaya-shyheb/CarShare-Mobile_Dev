import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});
  final String message;
  final int? statusCode;
  final String? code;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _secureStorage = FlutterSecureStorage();
  static const _tokenKey = 'carshare_access_token';
  static const _configuredBaseUrl = String.fromEnvironment(
    'CARSHARE_API_BASE_URL',
  );
  static final String baseUrl = _configuredBaseUrl.isNotEmpty
      ? _configuredBaseUrl
      : 'http://10.0.2.2:8081/api';

  Future<String?> readToken() => _secureStorage.read(key: _tokenKey);
  Future<void> saveToken(String token) =>
      _secureStorage.write(key: _tokenKey, value: token);
  Future<void> clearToken() => _secureStorage.delete(key: _tokenKey);

  Future<Map<String, dynamic>> get(String path) => _send('GET', path);
  Future<Map<String, dynamic>> post(
    String path, [
    Map<String, dynamic>? body,
  ]) => _send('POST', path, body: body);

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) =>
      _send('PUT', path, body: body);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final token = await readToken();
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (token != null) headers['Authorization'] = 'Bearer $token';
    try {
      final response = switch (method) {
        'GET' =>
          await http
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 15)),
        'PUT' =>
          await http
              .put(uri, headers: headers, body: jsonEncode(body ?? {}))
              .timeout(const Duration(seconds: 15)),
        _ =>
          await http
              .post(uri, headers: headers, body: jsonEncode(body ?? {}))
              .timeout(const Duration(seconds: 15)),
      };
      if (response.statusCode == 204 || response.body.isEmpty) {
        if (response.statusCode >= 200 && response.statusCode < 300) return {};
      }
      final dynamic decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
      final data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          data['detail'] as String? ?? _messageForStatus(response.statusCode),
          statusCode: response.statusCode,
          code: data['code'] as String?,
        );
      }
      return data;
    } on ApiException {
      rethrow;
    } on http.ClientException {
      throw const ApiException(
        'Connection problem. Check that the CarShare service is running and try again.',
      );
    } on TimeoutException {
      throw const ApiException('The request timed out. Please try again.');
    } on FormatException {
      throw const ApiException('The server returned an unreadable response.');
    }
  }

  String _messageForStatus(int status) => switch (status) {
    400 => 'Please check the information you entered.',
    401 => 'The email or password is incorrect.',
    409 => 'An account already exists for this email.',
    503 => 'The service is temporarily unavailable. Please try again later.',
    _ => 'We could not complete your request. Please try again.',
  };
}
