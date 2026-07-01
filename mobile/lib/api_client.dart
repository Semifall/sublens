import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  static const String baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://127.0.0.1:8000/api/v1');
  static String? jwtToken;

  static Map<String, String> get _headers {
    final headers = {'Content-Type': 'application/json'};
    if (jwtToken != null) {
      headers['Authorization'] = 'Bearer $jwtToken';
    }
    return headers;
  }

  /// Exchanges a mock Google OAuth Token for an App JWT token.
  static Future<Map<String, dynamic>> loginWithGoogle(String email, String name, String mockToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'google_oauth_token': mockToken,
        'email': email,
        'name': name,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      jwtToken = data['jwt_token'] as String;
      return data;
    } else {
      throw Exception('Failed to authenticate with Google: ${response.body}');
    }
  }

  /// Initiates an inbox scan using App JWT.
  static Future<String> startScan() async {
    final response = await http.post(
      Uri.parse('$baseUrl/scan'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['job_id'] as String;
    } else {
      throw Exception('Failed to start scan: ${response.body}');
    }
  }

  /// Polls the scan status and progress.
  static Future<Map<String, dynamic>> checkScanStatus(String jobId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/scan/$jobId'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to check scan status: ${response.body}');
    }
  }

  /// Retrieves the scan history log.
  static Future<List<dynamic>> getScanHistory() async {
    final response = await http.get(
      Uri.parse('$baseUrl/scan/history'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception('Failed to load scan history: ${response.body}');
    }
  }

  /// Retrieves subscriptions and Monthly spends.
  static Future<Map<String, dynamic>> getSubscriptions() async {
    final response = await http.get(
      Uri.parse('$baseUrl/subscriptions'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to load subscriptions: ${response.body}');
    }
  }

  /// Retrieves a detailed subscription with email logs.
  static Future<Map<String, dynamic>> getSubscriptionDetail(String id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/subscriptions/$id'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to load subscription detail: ${response.body}');
    }
  }

  /// Cancels a subscription.
  static Future<void> cancelSubscription(String id) async {
    final response = await http.post(
      Uri.parse('$baseUrl/subscriptions/$id/cancel'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to cancel subscription: ${response.body}');
    }
  }

  /// Retrieves aggregated insights.
  static Future<Map<String, dynamic>> getInsights() async {
    final response = await http.get(
      Uri.parse('$baseUrl/insights'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to load insights: ${response.body}');
    }
  }
}
