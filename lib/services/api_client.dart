import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  static const String _base = 'https://tallybridge-backend-950406969086.asia-south1.run.app';

  static const String _apiKey = 'sb_publishable_IRsM8wDF6w9OyiPegwB2cw_a9aqW9lt';

  static Future<Map<String, String>> _headers() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      'Content-Type': 'application/json',
      'x-api-key': _apiKey,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<dynamic> get(String path) async {
    final res = await http.get(
      Uri.parse('$_base$path'),
      headers: await _headers(),
    );
    if (res.statusCode == 401) throw Exception('Unauthorized');
    return jsonDecode(res.body);
  }

  // Returns raw response body (for CSV/text endpoints).
  static Future<String> getRaw(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final headers = await _headers();
    headers.remove('Content-Type');
    final res = await http.get(uri, headers: headers);
    if (res.statusCode == 401) throw Exception('Unauthorized');
    if (res.statusCode != 200) {
      throw Exception('Request failed: ${res.statusCode}');
    }
    return res.body;
  }

  static Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse('$_base$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    if (res.statusCode == 401) throw Exception('Unauthorized');
    return jsonDecode(res.body);
  }
}
