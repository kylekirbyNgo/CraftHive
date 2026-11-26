import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../core/config/supabase_config.dart';
import '../repositories/auth_repository.dart' show AppFailure, SupabaseAuthRepository, serverMessage;

/// Talks to the CraftHive REST API (supabase/functions/api/index.ts).
///
/// Every request is plain HTTP + JSON:
///   * the URL names a resource:   /api/v1/orders/{orderId}/payments
///   * the method says what to do: GET reads, POST creates, PUT replaces,
///                                 PATCH changes part of it, DELETE removes
///   * the status code says how it went (201 Created, 409 Conflict, 422 ...)
///   * the user's Supabase login token goes in the Authorization header,
///     so the server knows who is asking (the API is stateless).
class ApiClient {
  ApiClient(this._db, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final SupabaseClient _db;
  final http.Client _http;

  /// https://<project>.supabase.co/functions/v1/api/v1
  static String get baseUrl => '${SupabaseConfig.url}/functions/v1/api/v1';

  Future<ApiResponse> get(String path, {Map<String, String>? query}) => send('GET', path, query: query);
  Future<ApiResponse> post(String path, {Map<String, dynamic>? body}) => send('POST', path, body: body ?? const {});
  Future<ApiResponse> put(String path, {required Map<String, dynamic> body}) => send('PUT', path, body: body);
  Future<ApiResponse> patch(String path, {required Map<String, dynamic> body}) => send('PATCH', path, body: body);
  Future<ApiResponse> delete(String path) => send('DELETE', path);

  /// Sends one request. Throws [ApiException] (an [AppFailure] with a message
  /// for the user) when the API answers with an error status.
  Future<ApiResponse> send(String method, String path, {Map<String, dynamic>? body, Map<String, String>? query}) =>
      SupabaseAuthRepository.guard(() async {
        var uri = Uri.parse('$baseUrl$path');
        if (query != null && query.isNotEmpty) uri = uri.replace(queryParameters: query);
        final token = _db.auth.currentSession?.accessToken;
        final request = http.Request(method, uri)
          ..headers.addAll({
            'apikey': SupabaseConfig.anonKey,
            'Authorization': 'Bearer ${token ?? SupabaseConfig.anonKey}',
            'Accept': 'application/json',
            if (body != null) 'Content-Type': 'application/json',
          });
        if (body != null) request.body = jsonEncode(body);

        final response = await http.Response.fromStream(await _http.send(request));
        final data = _decode(response.body);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return ApiResponse(response.statusCode, data, response.headers['location']);
        }

        final error = data is Map && data['error'] is Map ? Map<String, dynamic>.from(data['error'] as Map) : const <String, dynamic>{};
        debugPrint('CraftHive API: $method $path → ${response.statusCode} ${error['code'] ?? response.body}');
        throw ApiException(
          _messageFor(response.statusCode, error),
          status: response.statusCode,
          code: (error['code'] as String?) ?? 'HTTP_${response.statusCode}',
          apiField: error['field'] as String?,
        );
      });

  static Object? _decode(String text) {
    if (text.trim().isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  static String _messageFor(int status, Map<String, dynamic> error) {
    final message = error['message'] as String?;
    if (status == 401) return 'Please log in again.';
    // Supabase answers 404 without our error shape when the function is not deployed.
    if (status == 404 && error.isEmpty) return 'The CraftHive API is not deployed yet (supabase/functions/api).';
    if (status >= 500 && status != 502) return serverMessage;
    return message ?? serverMessage;
  }
}

/// A successful answer: the status code, the JSON body and, for 201 Created,
/// the Location of the new resource.
class ApiResponse {
  const ApiResponse(this.status, this.data, this.location);

  final int status;
  final Object? data;
  final String? location;

  /// The body as one JSON object.
  Map<String, dynamic> get map => Map<String, dynamic>.from(data as Map);

  /// The body as a JSON list of objects.
  List<Map<String, dynamic>> get list => [for (final r in (data as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
}

/// An error answer from the API: {"error": {"code", "message", "field"}}.
/// [message] is written for the user; [code] is for the app to react to
/// (for example DUPLICATE_REFERENCE or FULLY_BOOKED).
class ApiException extends AppFailure {
  const ApiException(super.message, {required this.status, required this.code, this.apiField});

  final int status;
  final String code;

  /// The request field the error is about, such as "referenceNumber".
  final String? apiField;
}
