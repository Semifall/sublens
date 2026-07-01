import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  static const String baseUrl = 'http://127.0.0.1:8000/api/v1';

  /// Initiates an inbox scan using the provided access token.
  /// Returns the jobId.
  static Future<String> startScan(String accessToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/scan'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'access_token': accessToken}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['job_id'] as String;
    } else {
      throw Exception('Failed to start inbox scan: ${response.body}');
    }
  }

  /// Polls the scan status and results for the given jobId.
  /// Returns a map containing: status, progress, summary, subscriptions.
  static Future<Map<String, dynamic>> checkScanStatus(String jobId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/scan/$jobId'),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to check scan status: ${response.body}');
    }
  }

  /// Submits a decision event recording the user's action on a subscription.
  static Future<void> submitDecisionEvent({
    required String subscriptionId,
    required String userAction,
    required String aiRecommendation,
    required double confidence,
    required double impactValue,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/decision-events'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'subscription_id': subscriptionId,
        'user_action': userAction,
        'ai_recommendation': aiRecommendation,
        'confidence': confidence,
        'impact_value': impactValue,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to submit decision event: ${response.body}');
    }
  }
}
