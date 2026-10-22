import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/config_url.dart';

class ApiClient {
  String get baseUrl => ConfigUrl.baseUrl;

  ApiClient();

  Future<Map<String, String>> _buildHeaders([Map<String, String>? extraHeaders]) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    if (extraHeaders != null) {
      headers.addAll(extraHeaders);
    }
    return headers;
  }

  static const Duration timeoutDuration = Duration(seconds: 10);

  Future<http.Response> get(String endpoint, {Map<String, String>? headers}) async {
    final finalHeaders = await _buildHeaders(headers);
    return http
        .get(Uri.parse('$baseUrl$endpoint'), headers: finalHeaders)
        .timeout(timeoutDuration);
  }

  Future<http.Response> post(String endpoint, {Map<String, String>? headers, dynamic body}) async {
    final finalHeaders = await _buildHeaders(headers);
    return http
        .post(
          Uri.parse('$baseUrl$endpoint'),
          headers: finalHeaders,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(timeoutDuration);
  }

  Future<http.Response> put(String endpoint, {Map<String, String>? headers, dynamic body}) async {
    final finalHeaders = await _buildHeaders(headers);
    return http
        .put(
          Uri.parse('$baseUrl$endpoint'),
          headers: finalHeaders,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(timeoutDuration);
  }

  Future<http.Response> delete(String endpoint, {Map<String, String>? headers}) async {
    final finalHeaders = await _buildHeaders(headers);
    return http
        .delete(Uri.parse('$baseUrl$endpoint'), headers: finalHeaders)
        .timeout(timeoutDuration);
  }
}
