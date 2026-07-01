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

  /// Retrieves decision drift analytics.
  static Future<Map<String, dynamic>> getAnalyticsDrift() async {
    final response = await http.get(Uri.parse('$baseUrl/analytics/drift'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to load drift analytics: ${response.body}');
    }
  }

  /// Retrieves value loop analytics (money saved, missed, accuracy).
  static Future<Map<String, dynamic>> getAnalyticsValue() async {
    final response = await http.get(Uri.parse('$baseUrl/analytics/value'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to load value analytics: ${response.body}');
    }
  }

  /// Sends a single core behavior event to the tracking system.
  static Future<void> trackEvent(Map<String, dynamic> event) async {
    final response = await http.post(
      Uri.parse('$baseUrl/events'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(event),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to log event: ${response.body}');
    }
  }

  /// Sends a batch of behavior events for client throttling.
  static Future<void> trackEventsBatch(List<Map<String, dynamic>> events) async {
    final response = await http.post(
      Uri.parse('$baseUrl/events/batch'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(events),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to log batch events: ${response.body}');
    }
  }

  /// Retrieves A/B test metrics comparison.
  static Future<Map<String, dynamic>> getAnalyticsABTest() async {
    final response = await http.get(Uri.parse('$baseUrl/analytics/abtest'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to load AB test analytics: ${response.body}');
    }
  }

  /// Triggers self-optimization loop (mines errors, proposes fix, elevates baseline).
  static Future<Map<String, dynamic>> triggerSelfOptimization() async {
    final response = await http.post(Uri.parse('$baseUrl/analytics/self-optimize'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to trigger self-optimization: ${response.body}');
    }
  }

  /// Retrieves user psychological state evaluation.
  static Future<Map<String, dynamic>> getUserState(String userId) async {
    final response = await http.get(Uri.parse('$baseUrl/user/state/$userId'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to load user state: ${response.body}');
    }
  }

  /// Retrieves user long-term memory layers and dynamic persona settings.
  static Future<Map<String, dynamic>> getUserPersona(String userId) async {
    final response = await http.get(Uri.parse('$baseUrl/user/persona/$userId'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to load user persona: ${response.body}');
    }
  }

  /// Creates a multi-step ActionPlan based on user intent.
  static Future<Map<String, dynamic>> createActionPlan(String intent, String userId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/action/plan'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'intent': intent, 'user_id': userId}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to plan actions: ${response.body}');
    }
  }

  /// Executes ActionPlan sequentially via Tool Executor.
  static Future<Map<String, dynamic>> executeActionPlan(Map<String, dynamic> plan, String userId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/action/execute?user_id=$userId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(plan),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to execute plan: ${response.body}');
    }
  }

  /// Retrieves evaluated proactive nudge/trigger.
  static Future<Map<String, dynamic>> getProactiveTrigger(String userId) async {
    final response = await http.get(Uri.parse('$baseUrl/autonomous/trigger/$userId'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to load proactive trigger: ${response.body}');
    }
  }

  /// Utility to reset trigger cooldown timer.
  static Future<void> resetTriggerCooldown() async {
    final response = await http.post(Uri.parse('$baseUrl/autonomous/reset-cooldown'));
    if (response.statusCode != 200) {
      throw Exception('Failed to reset trigger cooldown: ${response.body}');
    }
  }
}
