import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
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
  Future<List<Map<String, dynamic>>> getList(String path) async {
    final token = await readToken();
    final headers = <String, String>{'Accept': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    try {
      final response = await http
          .get(Uri.parse('$baseUrl$path'), headers: headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        dynamic decoded;
        try {
          decoded = jsonDecode(response.body);
        } on FormatException {
          decoded = null;
        }
        final data = decoded is Map<String, dynamic>
            ? decoded
            : <String, dynamic>{};
        throw ApiException(
          data['detail'] as String? ?? _messageForStatus(response.statusCode),
          statusCode: response.statusCode,
          code: data['code'] as String?,
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const ApiException('The server returned an unreadable response.');
      }
      return decoded.cast<Map<String, dynamic>>();
    } on ApiException {
      rethrow;
    } on SocketException {
      throw ApiException(_connectionErrorMessage);
    } on TimeoutException {
      throw const ApiException(
        'The CarShare service did not respond. Check that the backend is running, then try again.',
      );
    } on http.ClientException {
      throw ApiException(_connectionErrorMessage);
    } on FormatException {
      throw const ApiException('The server returned an unreadable response.');
    }
  }

  Future<Map<String, dynamic>> post(
    String path, [
    Map<String, dynamic>? body,
  ]) => _send('POST', path, body: body);

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) =>
      _send('PUT', path, body: body);

  Future<Map<String, dynamic>> delete(
    String path, [
    Map<String, dynamic>? body,
  ]) => _send('DELETE', path, body: body);

  Future<void> uploadPhoto({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final token = await readToken();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/users/me/photo'),
    );
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      http.MultipartFile.fromBytes(
        'photo',
        bytes,
        filename: fileName,
        contentType: MediaType.parse(mimeType),
      ),
    );
    try {
      final streamed = await request.send().timeout(
        const Duration(seconds: 20),
      );
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final response = await http.Response.fromStream(streamed);
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        throw ApiException(
          data['detail'] as String? ?? _messageForStatus(response.statusCode),
          statusCode: response.statusCode,
          code: data['code'] as String?,
        );
      }
    } on ApiException {
      rethrow;
    } on SocketException {
      throw ApiException(_connectionErrorMessage);
    } on TimeoutException {
      throw const ApiException(
        'The CarShare service did not respond. Check that the backend is running, then try again.',
      );
    } on http.ClientException {
      throw ApiException(_connectionErrorMessage);
    }
  }

  Future<Uint8List> getPhotoBytes() async {
    final token = await readToken();
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/users/me/photo'),
            headers: {if (token != null) 'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          _messageForStatus(response.statusCode),
          statusCode: response.statusCode,
        );
      }
      return response.bodyBytes;
    } on ApiException {
      rethrow;
    } on SocketException {
      throw ApiException(_connectionErrorMessage);
    } on TimeoutException {
      throw const ApiException(
        'The CarShare service did not respond. Check that the backend is running, then try again.',
      );
    } on http.ClientException {
      throw ApiException(_connectionErrorMessage);
    }
  }

  Future<void> deletePhoto() async {
    await _send('DELETE', '/users/me/photo');
  }

  Future<Map<String, dynamic>> uploadMultipart({
    required String path,
    required String fieldName,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final token = await readToken();
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      http.MultipartFile.fromBytes(
        fieldName,
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
        throw _exceptionForResponse(response.statusCode, response.body);
      }
      if (response.body.isEmpty) return {};
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw const ApiException('The server returned an unreadable response.');
    } on ApiException {
      rethrow;
    } on SocketException {
      throw ApiException(_connectionErrorMessage);
    } on TimeoutException {
      throw const ApiException(
        'The CarShare service did not respond. Check that the backend is running, then try again.',
      );
    } on HandshakeException {
      throw const ApiException(
        'Could not establish a secure connection to the CarShare service.',
      );
    } on http.ClientException {
      throw ApiException(_connectionErrorMessage);
    } on FormatException {
      throw const ApiException('The server returned an unreadable response.');
    }
  }

  Future<Uint8List> getBytes(String path) async {
    final token = await readToken();
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl$path'),
            headers: {if (token != null) 'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _exceptionForResponse(response.statusCode, response.body);
      }
      return response.bodyBytes;
    } on ApiException {
      rethrow;
    } on SocketException {
      throw ApiException(_connectionErrorMessage);
    } on TimeoutException {
      throw const ApiException(
        'The CarShare service did not respond. Check that the backend is running, then try again.',
      );
    } on HandshakeException {
      throw const ApiException(
        'Could not establish a secure connection to the CarShare service.',
      );
    } on http.ClientException {
      throw ApiException(_connectionErrorMessage);
    }
  }

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
        'DELETE' =>
          await http
              .delete(
                uri,
                headers: headers,
                body: body == null ? null : jsonEncode(body),
              )
              .timeout(const Duration(seconds: 15)),
        _ =>
          await http
              .post(uri, headers: headers, body: jsonEncode(body ?? {}))
              .timeout(const Duration(seconds: 15)),
      };
      if (response.statusCode == 204 || response.body.isEmpty) {
        if (response.statusCode >= 200 && response.statusCode < 300) return {};
      }
      dynamic decoded;
      try {
        decoded = response.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(response.body);
      } on FormatException {
        final status = response.statusCode;
        if (status < 200 || status >= 300) {
          throw ApiException(
            'The server returned HTTP $status. Check that the CarShare backend is running and reachable.',
            statusCode: status,
          );
        }
        throw const ApiException('The server returned an unreadable response.');
      }
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
    } on SocketException {
      throw ApiException(_connectionErrorMessage);
    } on HandshakeException {
      throw const ApiException(
        'Could not establish a secure connection to the CarShare service.',
      );
    } on http.ClientException {
      throw ApiException(_connectionErrorMessage);
    } on TimeoutException {
      throw const ApiException(
        'The CarShare service did not respond. Check that the backend is running, then try again.',
      );
    }
  }

  ApiException _exceptionForResponse(int statusCode, String body) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      decoded = null;
    }
    final data = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};
    return ApiException(
      data['detail'] as String? ?? _messageForStatus(statusCode),
      statusCode: statusCode,
      code: data['code'] as String?,
    );
  }

  String get _connectionErrorMessage {
    final host = Uri.tryParse(baseUrl)?.host;
    if (host == '127.0.0.1' || host == 'localhost') {
      return 'Cannot reach the backend from this phone. Keep it connected by USB, restart the backend, and run run-android-phone.ps1 again.';
    }
    return 'Cannot reach the CarShare backend. Start the backend and check the emulator or network connection.';
  }

  String _messageForStatus(int status) => switch (status) {
    400 => 'Please check the information you entered.',
    401 => 'The email or password is incorrect.',
    403 => 'The server blocked this request. Request a fresh password reset link and try again.',
    409 => 'An account already exists for this email.',
    423 => 'Too many incorrect attempts. Try again in 15 minutes.',
    503 => 'The service is temporarily unavailable. Please try again later.',
    _ => 'We could not complete your request. Please try again.',
  };
}
