import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';

import '../core/config.dart';

class ApiClient {
  static const String _base = Config.backendBaseUrl;

  /// Shared HTTP client for all backend calls. SentryHttpClient records a
  /// breadcrumb for every request (so a later crash carries the call history)
  /// and, when a span is active, propagates the sentry-trace header. Automatic
  /// failed-request capture is OFF — we capture explicitly below so we can
  /// attach the request id and response body.
  static final http.Client client = SentryHttpClient(
    captureFailedRequests: false,
  );

  static final Random _rng = Random();

  /// A short, unique-enough correlation id sent as `x-request-id`. The backend
  /// echoes it and tags its Sentry scope with it, so an in-app failure event and
  /// the backend exception share one request_id.
  static String newRequestId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
      '-${_rng.nextInt(0x7fffffff).toRadixString(16)}';

  static Future<Map<String, String>> _headers(String requestId) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      'Content-Type': 'application/json',
      'x-api-key': Config.mrpApiKey,
      'x-request-id': requestId,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Records a failed backend interaction as a Sentry event, tagged with the
  /// correlation id, endpoint, and (for HTTP failures) status + response body.
  /// Safe to call from any backend call site (e.g. the push-to-Tally activate).
  static void reportFailure(
    String method,
    String path,
    String requestId, {
    int? status,
    String? body,
    Object? error,
    StackTrace? stack,
  }) {
    Sentry.captureException(
      error ??
          Exception(
            'Backend $method $path failed${status != null ? ' ($status)' : ''}',
          ),
      stackTrace: stack,
      withScope: (scope) {
        scope.level = SentryLevel.error;
        scope.setTag('request_id', requestId);
        scope.setTag('endpoint', path);
        scope.setTag('http_method', method);
        if (status != null) scope.setTag('http_status', '$status');
        if (body != null && body.isNotEmpty) {
          scope.setContexts('response', {
            'body': body.length > 2000 ? '${body.substring(0, 2000)}…' : body,
          });
        }
      },
    );
  }

  static Future<dynamic> get(String path) async {
    final requestId = newRequestId();
    final http.Response res;
    try {
      res = await client.get(
        Uri.parse('$_base$path'),
        headers: await _headers(requestId),
      );
    } catch (e, st) {
      reportFailure('GET', path, requestId, error: e, stack: st);
      rethrow;
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      reportFailure('GET', path, requestId,
          status: res.statusCode, body: res.body);
    }
    if (res.statusCode == 401) throw Exception('Unauthorized');
    return jsonDecode(res.body);
  }

  // Returns raw response body (for CSV/text endpoints).
  static Future<String> getRaw(String path, {Map<String, String>? query}) async {
    final requestId = newRequestId();
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final headers = await _headers(requestId);
    headers.remove('Content-Type');
    final http.Response res;
    try {
      res = await client.get(uri, headers: headers);
    } catch (e, st) {
      reportFailure('GET', path, requestId, error: e, stack: st);
      rethrow;
    }
    if (res.statusCode != 200) {
      reportFailure('GET', path, requestId,
          status: res.statusCode, body: res.body);
      if (res.statusCode == 401) throw Exception('Unauthorized');
      throw Exception('Request failed: ${res.statusCode}');
    }
    return res.body;
  }

  // Returns the raw response bytes (for binary endpoints like invoice images).
  static Future<Uint8List> getBytes(String path) async {
    final requestId = newRequestId();
    final headers = await _headers(requestId);
    headers.remove('Content-Type');
    final http.Response res;
    try {
      res = await client.get(Uri.parse('$_base$path'), headers: headers);
    } catch (e, st) {
      reportFailure('GET', path, requestId, error: e, stack: st);
      rethrow;
    }
    if (res.statusCode != 200) {
      reportFailure('GET', path, requestId, status: res.statusCode);
      if (res.statusCode == 401) throw Exception('Unauthorized');
      throw Exception('Request failed: ${res.statusCode}');
    }
    return res.bodyBytes;
  }

  static Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final requestId = newRequestId();
    final http.Response res;
    try {
      res = await client.post(
        Uri.parse('$_base$path'),
        headers: await _headers(requestId),
        body: jsonEncode(body),
      );
    } catch (e, st) {
      reportFailure('POST', path, requestId, error: e, stack: st);
      rethrow;
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      reportFailure('POST', path, requestId,
          status: res.statusCode, body: res.body);
    }
    if (res.statusCode == 401) throw Exception('Unauthorized');
    return jsonDecode(res.body);
  }
}
