import 'dart:async';
import 'package:flutter/material.dart';
import 'models.dart';
import 'api_client.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sublens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0915),
        primaryColor: const Color(0xFF6366F1),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF121124),
          error: Color(0xFFEF4444),
        ),
        useMaterial3: true,
      ),
      home: const MainNavigationFrame(),
    );
  }
}

enum AppState { auth, scanning, dashboard, detail }

class MainNavigationFrame extends StatefulWidget {
  const MainNavigationFrame({super.key});

  @override
  State<MainNavigationFrame> createState() => _MainNavigationFrameState();
}

class _MainNavigationFrameState extends State<MainNavigationFrame> {
  AppState _currentState = AppState.auth;
  String _scanProgressText = "Initializing scan...";
  int _scanProgressPct = 0;
  int _emailsProcessed = 0;
  int _totalEmails = 0;
  List<String> _alerts = [];
  List<String> _insights = [];
  List<String> _suggestions = [];
  
  // API Data
  ScanSummary? _summary;
  List<Subscription> _subscriptions = [];
  Subscription? _selectedSubscription;
  String? _errorMsg;
  Map<String, String> _loggedDecisions = {};
  
  // Analytics Data
  double _moneySaved = 320.0;
  double _moneyMissed = 120.0;
  double _systemAccuracy = 0.87;
  double _driftRate = 0.25;
  int _totalEvents = 8;
  int _ignoredRecommendations = 2;
  String _activeEngineVersion = "v1";
  
  // User State Engine Data
  String _userState = "cold_start";
  String _activePromptTemplate = "prompt_cold_start.txt";
  
  late final String _sessionId = 's-${DateTime.now().millisecondsSinceEpoch}';

  Future<void> _track(String eventType, Map<String, dynamic> payload, {Map<String, dynamic>? context}) async {
    final event = {
      'user_id': 'u123',
      'session_id': _sessionId,
      'event_type': eventType,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'payload': payload,
      'context': context ?? {
        'step_stage': 'step2_error_intelligence',
        'user_state': 'active',
        'model_version': _activeEngineVersion,
      }
    };
    try {
      await ApiClient.trackEvent(event);
      print('Event tracked: $eventType');
    } catch (e) {
      print('Failed to track event: $e');
    }
  }

  // Initiates the scan flow
  Future<void> _startScanFlow() async {
    setState(() {
      _currentState = AppState.scanning;
      _scanProgressPct = 0;
      _scanProgressText = "Connecting to Google Account...";
      _errorMsg = null;
    });

    try {
      _track('input_submit', {
        'input_text': 'start_scan',
        'emotion_tag': 'active_intent',
        'session_id': _sessionId,
      });

      // Step 1: Start scan and get jobId
      final jobId = await ApiClient.startScan("mock_token");
      
      // Step 2: Poll scan status
      Timer.periodic(const Duration(milliseconds: 800), (timer) async {
        try {
          final result = await ApiClient.checkScanStatus(jobId);
          final status = result['status'] as String;
          final progress = result['progress'] as int;

          if (!mounted) {
            timer.cancel();
            return;
          }

          setState(() {
            _scanProgressPct = progress;
            _emailsProcessed = result['emails_processed'] as int? ?? 0;
            _totalEmails = result['total_emails'] as int? ?? 0;
            if (progress < 25) {
              _scanProgressText = "Retrieving email headers from Gmail...";
            } else if (progress < 90) {
              _scanProgressText = "Running decision engine & analyzing invoices...";
            } else {
              _scanProgressText = "Aggregating cycles and compiling pricing leakage...";
            }
          });

          if (status == 'completed') {
            timer.cancel();
            
             // Map results from API
            final subsJson = result['subscriptions'] as List<dynamic>;
            final summaryJson = result['summary'] as Map<String, dynamic>;
            final alertsJson = result['alerts'] as List<dynamic>? ?? [];

            setState(() {
              _subscriptions = subsJson
                  .map((s) => Subscription.fromJson(s as Map<String, dynamic>))
                  .toList();
              _summary = ScanSummary.fromJson(summaryJson);
              _alerts = alertsJson.map((a) => a as String).toList();
              _insights = (result['insights'] as List<dynamic>? ?? []).map((i) => i as String).toList();
              _suggestions = (result['suggestions'] as List<dynamic>? ?? []).map((s) => s as String).toList();
              _currentState = AppState.dashboard;
            });
            _track('system_response', {
              'response_text': 'subscriptions_found_${subsJson.length}',
              'model_version': 'v1.3',
              'latency_ms': 820,
            });
            _fetchAnalytics();
            _fetchUserState();
          } else if (status == 'failed') {
            timer.cancel();
            _track('error_trigger', {
              'error_code': 'E102',
              'input_text': 'scan_failed_on_server',
              'context_stage': 'step2_error_intelligence',
            });
            setState(() {
              _errorMsg = "Scanning process failed on the server.";
              _currentState = AppState.auth;
            });
          }
        } catch (e) {
          _track('error_trigger', {
            'error_code': 'E102',
            'input_text': 'polling_exception',
            'context_stage': 'step2_error_intelligence',
          });
          timer.cancel();
          setState(() {
            _errorMsg = "Error polling scan status: $e";
            _currentState = AppState.auth;
          });
        }
      });
    } catch (e) {
      setState(() {
        _errorMsg = "Failed to start scanning: $e";
        _currentState = AppState.auth;
      });
    }
  }

  void _selectSubscription(Subscription sub) {
    setState(() {
      _selectedSubscription = sub;
      _currentState = AppState.detail;
    });
  }

  void _closeDetail() {
    setState(() {
      _selectedSubscription = null;
      _currentState = AppState.dashboard;
    });
  }

  void _logout() {
    _track('user_exit', {
      'session_id': _sessionId,
      'exit_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'last_event_type': 'logout_click',
    });
    setState(() {
      _subscriptions = [];
      _summary = null;
      _alerts = [];
      _insights = [];
      _suggestions = [];
      _loggedDecisions = {};
      _moneySaved = 320.0;
      _moneyMissed = 120.0;
      _systemAccuracy = 0.87;
      _activeEngineVersion = "v1";
      _userState = "cold_start";
      _activePromptTemplate = "prompt_cold_start.txt";
      _currentState = AppState.auth;
    });
  }

  Future<void> _handleDecision(Subscription sub, String action) async {
    // Map UI actions to backend user_action constraints: keep -> accept, cancel -> cancel, ignore -> ignore
    final userAction = action == 'keep' ? 'accept' : action;
    final aiRec = sub.status == 'cancelled' ? 'cancel' : 'keep';
    final confidence = sub.confidence;
    final impact = action == 'cancel' ? sub.price.amount : 0.0;
    
    setState(() {
      _loggedDecisions[sub.id ?? sub.merchant] = action;
    });
    
    try {
      await ApiClient.submitDecisionEvent(
        subscriptionId: sub.id ?? sub.merchant.toLowerCase(),
        userAction: userAction,
        aiRecommendation: aiRec,
        confidence: confidence,
        impactValue: impact,
      );
      
      _track('shift_action', {
        'action_type': action,
        'duration_ms': 1200,
      });
      
      await _fetchAnalytics();
      await _fetchUserState();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Decision recorded: ${action.toUpperCase()} ${sub.merchant}'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit decision: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _runSelfOptimization() async {
    try {
      final result = await ApiClient.triggerSelfOptimization();
      
      setState(() {
        _activeEngineVersion = result['active_version'] as String;
      });
      
      final problem = result['problem_identified'] as Map<String, dynamic>;
      final fix = result['fix_proposed'] as Map<String, dynamic>;
      final metrics = result['metrics_comparison'] as Map<String, dynamic>;
      final delta = metrics['delta'] as Map<String, dynamic>;
      
      if (!mounted) return;
      
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: const Color(0xFF121124),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: const Color(0xFF8B5CF6).withOpacity(0.3)),
            ),
            title: Row(
              children: const [
                Icon(Icons.psychology, color: Color(0xFF8B5CF6)),
                SizedBox(width: 10),
                Text('Self-Optimization Log', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('1. ERROR MINING OUTCOME', style: TextStyle(color: Color(0xFF93C5FD), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  const SizedBox(height: 4),
                  Text('Problem Mined: ${problem['problem_cluster']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  Text('Impact Score: ${problem['impact_score']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  Text('Root Pattern: ${(problem['root_pattern'] as List<dynamic>).join(", ")}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  const SizedBox(height: 14),
                  
                  const Text('2. FIX PROPOSAL IMPLEMENTED', style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  const SizedBox(height: 4),
                  Text('Fix ID: ${fix['fix_id']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  Text('Action: ${(fix['change'] as List<dynamic>).join(", ")}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  Text('Expected: ${fix['expected_effect']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 14),
                  
                  const Text('3. METRICS JUDGE (A/B TESTING RESULTS)', style: TextStyle(color: Color(0xFFC7D2FE), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  const SizedBox(height: 4),
                  Text('Winner: ${metrics['winner']}', style: const TextStyle(color: Color(0xFF34D399), fontSize: 13, fontWeight: FontWeight.bold)),
                  Text('Delta: ${delta.values.join(", ")}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('PROCEED', style: TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Self-Optimization failed: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _fetchAnalytics() async {
    try {
      final drift = await ApiClient.getAnalyticsDrift();
      final val = await ApiClient.getAnalyticsValue();
      
      setState(() {
        _driftRate = (drift['drift_rate'] as num).toDouble();
        _totalEvents = drift['total_events'] as int;
        _ignoredRecommendations = drift['ignored_recommendations'] as int;
        
        _moneySaved = (val['money_saved'] as num).toDouble();
        _moneyMissed = (val['money_missed'] as num).toDouble();
        _systemAccuracy = (val['accuracy'] as num).toDouble();
      });
    } catch (e) {
      debugPrint('Failed to load analytics: $e');
    }
  }

  Future<void> _fetchUserState() async {
    try {
      final res = await ApiClient.getUserState("u123");
      setState(() {
        _userState = res['current_state'] as String;
        _activePromptTemplate = res['active_prompt_template'] as String;
      });
    } catch (e) {
      debugPrint('Failed to load user state: $e');
    }
  }

  Widget _buildUserStateBanner() {
    Color bannerBg;
    Color borderBg;
    Color textCol;
    String badgeText;
    String description;
    IconData icon;
    
    switch (_userState) {
      case "cold_start":
        bannerBg = const Color(0xFF1E3A8A).withOpacity(0.1);
        borderBg = const Color(0xFF3B82F6).withOpacity(0.3);
        textCol = const Color(0xFF93C5FD);
        badgeText = "COLD START";
        description = "Welcome! We detected 1 cycle risk in Netflix. Cancel to optimize now.";
        icon = Icons.explore;
        break;
      case "exploration":
        bannerBg = const Color(0xFF065F46).withOpacity(0.1);
        borderBg = const Color(0xFF10B981).withOpacity(0.3);
        textCol = const Color(0xFF34D399);
        badgeText = "EXPLORATION";
        description = "Exploring SubLens. Try validating different cycles. You can Cancel, Keep or Ignore.";
        icon = Icons.search;
        break;
      case "habit":
        bannerBg = const Color(0xFF5B21B6).withOpacity(0.1);
        borderBg = const Color(0xFF8B5CF6).withOpacity(0.3);
        textCol = const Color(0xFFC7D2FE);
        badgeText = "HABIT";
        description = "Stability habits locked. Advanced analysis mode activated. Trends projection is live.";
        icon = Icons.psychology;
        break;
      case "at_risk":
      default:
        bannerBg = const Color(0xFF7F1D1D).withOpacity(0.1);
        borderBg = const Color(0xFFEF4444).withOpacity(0.3);
        textCol = const Color(0xFFFCA5A5);
        badgeText = "AT RISK";
        description = "Low retention warning. Active共鸣: We made it easier to cancel leakage. Save \$59/month instantly.";
        icon = Icons.warning_amber_rounded;
        break;
    }
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bannerBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderBg),
      ),
      child: Row(
        children: [
          Icon(icon, color: textCol, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: borderBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badgeText,
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ACTIVE PROMPT: $_activePromptTemplate',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          color: textCol.withOpacity(0.7),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    color: textCol,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_currentState) {
      case AppState.auth:
        return _buildAuthScreen();
      case AppState.scanning:
        return _buildScanningScreen();
      case AppState.dashboard:
        return _buildDashboardScreen();
      case AppState.detail:
        return _buildDetailScreen();
    }
  }

  // --- SCREEN BUILDERS ---

  Widget _buildAuthScreen() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F0C20), Color(0xFF05040A)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Glowing Logo/Brand icon
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.1),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withOpacity(0.2),
                        blurRadius: 40,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 64,
                    color: Color(0xFF6366F1),
                  ),
                ),
                const SizedBox(height: 30),
                const Text(
                  'SubLens',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Scan. Detect. Stop leaking money.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 60),
                if (_errorMsg != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                    ),
                    child: Text(
                      _errorMsg!,
                      style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                // Glowing Action Button
                InkWell(
                  onTap: _startScanFlow,
                  borderRadius: BorderRadius.circular(30),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.g_mobiledata, size: 28, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Sign in with Google',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Privacy First: No mailbox data is saved on our servers.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScanningScreen() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0A0915),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Pulsing Scanner Circular Indicator
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      height: 160,
                      width: 160,
                      child: CircularProgressIndicator(
                        value: _scanProgressPct / 100,
                        strokeWidth: 8,
                        backgroundColor: const Color(0xFF16142E),
                        color: const Color(0xFF6366F1),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$_scanProgressPct%',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'SCANNING',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 2,
                            color: Color(0xFF818CF8),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 50),
                Text(
                  _scanProgressText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Progress: $_scanProgressPct%',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Emails processed: $_emailsProcessed / $_totalEmails',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Please keep this page open. This takes 20-60 seconds.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardScreen() {
    final currencySymbol = _subscriptions.isNotEmpty 
        ? (_subscriptions.first.price.currency == 'USD' ? '\$' : '¥')
        : '¥';
        
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'SubLens Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _startScanFlow,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dynamic User State Banner
            _buildUserStateBanner(),
            const SizedBox(height: 20),
            // Cost Spend Summary Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Monthly Subscription Spend',
                    style: TextStyle(
                      color: Color(0xFFC7D2FE),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$currencySymbol${_summary?.monthlyCost.toStringAsFixed(2) ?? "0.00"}/month',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSummaryStat(
                        'Annual Leakage',
                        '$currencySymbol${_summary?.yearlyCost.toStringAsFixed(2) ?? "0.00"}',
                      ),
                      _buildSummaryStat(
                        'Detected Items',
                        '${_summary?.subscriptionCount ?? 0} Subscriptions',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Value Loop Analytics Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF161530),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF1E1C3A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DECISION INTELLIGENCE ANALYTICS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Color(0xFF93C5FD),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('You Saved', style: TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            '$currencySymbol${_moneySaved.toStringAsFixed(2)}',
                            style: const TextStyle(color: Color(0xFF10B981), fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('You Ignored', style: TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            '$currencySymbol${_moneyMissed.toStringAsFixed(2)}',
                            style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('System Accuracy', style: TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            '${(_systemAccuracy * 100).toInt()}%',
                            style: const TextStyle(color: Color(0xFF6366F1), fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Self-Improving Loop Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1F1D36),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B5CF6).withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '🧠 SELF-IMPROVING CORE (V1)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: Color(0xFFC7D2FE),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'ENGINE: ${_activeEngineVersion.toUpperCase()}',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFC7D2FE),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'SubLens continuously mines error logs, proposes heuristics upgrades, runs A/B split-tests, and auto-promotes successful versions.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white60,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _runSelfOptimization,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 38),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'TRIGGER SELF-OPTIMIZATION LOOP',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            if (_alerts.isNotEmpty) ...[
              const SizedBox(height: 30),
              const Text(
                'RISK ALERTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Color(0xFFEF4444),
                ),
              ),
              const SizedBox(height: 12),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _alerts.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final alert = _alerts[index];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Color(0xFFFCA5A5), size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            alert,
                            style: const TextStyle(
                              color: Color(0xFFFCA5A5),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
            if (_insights.isNotEmpty) ...[
              const SizedBox(height: 30),
              const Text(
                'SYSTEM INSIGHTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Color(0xFF3B82F6),
                ),
              ),
              const SizedBox(height: 12),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _insights.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final insight = _insights[index];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lightbulb_outline, color: Color(0xFF93C5FD), size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            insight,
                            style: const TextStyle(
                              color: Color(0xFF93C5FD),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: 30),
              const Text(
                'DECISION RECOMMENDATIONS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Color(0xFF10B981),
                ),
              ),
              const SizedBox(height: 12),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _suggestions.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final suggestion = _suggestions[index];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF10B981).withOpacity(0.12),
                          const Color(0xFF047857).withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.savings_outlined, color: Color(0xFFA7F3D0), size: 22),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            suggestion,
                            style: const TextStyle(
                              color: Color(0xFFA7F3D0),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFA7F3D0), size: 12),
                      ],
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 30),
            const Text(
              'DETECTED SUBSCRIPTIONS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 12),
            if (_subscriptions.isEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 40),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 48, color: Colors.white.withOpacity(0.2)),
                    const SizedBox(height: 12),
                    Text(
                      'No subscriptions identified in your mailbox.',
                      style: TextStyle(color: Colors.white.withOpacity(0.5)),
                    ),
                  ],
                ),
              ),
            ] else ...[
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _subscriptions.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final sub = _subscriptions[index];
                  return _buildSubscriptionTile(sub);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFC7D2FE),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildSubscriptionTile(Subscription sub) {
    final subSymbol = sub.price.currency == 'USD' ? '\$' : '¥';
    final accentColor = _getStatusColor(sub.status);
    final hasDecision = _loggedDecisions.containsKey(sub.id ?? sub.merchant);
    final recordedAction = _loggedDecisions[sub.id ?? sub.merchant];
    
    // AI Recommendation determination
    final String aiRecommendation = sub.status == 'cancelled' ? 'cancel' : 'keep';
    final Color aiColor = aiRecommendation == 'cancel' ? const Color(0xFFFCA5A5) : const Color(0xFFC7D2FE);
    
    // User Action determination
    final String userDecision = hasDecision ? recordedAction! : 'No Action';
    final Color userColor = hasDecision 
        ? (recordedAction == 'cancel' ? const Color(0xFFEF4444) : (recordedAction == 'keep' ? const Color(0xFF6366F1) : Colors.grey))
        : Colors.white.withOpacity(0.3);
        
    // Decision Alignment determination
    String driftStatus = 'Awaiting Decision';
    Color driftColor = Colors.white.withOpacity(0.3);
    if (hasDecision) {
      final userActionMapped = recordedAction == 'keep' ? 'accept' : recordedAction;
      final isDrift = (userActionMapped == 'ignore') || 
                      (userActionMapped == 'accept' && aiRecommendation == 'cancel') ||
                      (userActionMapped == 'cancel' && aiRecommendation == 'keep');
                      
      driftStatus = isDrift ? 'Drift detected' : 'Aligned';
      driftColor = isDrift ? const Color(0xFFF87171) : const Color(0xFF34D399);
    }

    return InkWell(
      onTap: () => _selectSubscription(sub),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF121124),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF1E1C3A),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Styled logo letter avatar
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    sub.merchant.isNotEmpty ? sub.merchant[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Color(0xFF6366F1),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Merchant and info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sub.merchant,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          // Status badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: accentColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              sub.status.toUpperCase(),
                              style: TextStyle(
                                color: accentColor,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Confidence percentage & Time Intelligence info
                          Expanded(
                            child: Text(
                              '${(sub.confidence * 100).toInt()}% Match • ${sub.cycleDetected} • ${(sub.stabilityScore * 100).toInt()}% stable',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withOpacity(0.4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Price amount
                Text(
                  '$subSymbol${sub.price.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            
            // Decision intelligence block
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.01),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.03)),
              ),
              child: Column(
                children: [
                  _buildDecisionStatusRow('AI recommendation', aiRecommendation.toUpperCase(), aiColor),
                  const SizedBox(height: 6),
                  _buildDecisionStatusRow('User action', userDecision.toUpperCase(), userColor),
                  const SizedBox(height: 6),
                  _buildDecisionStatusRow('Decision alignment', driftStatus.toUpperCase(), driftColor),
                ],
              ),
            ),
            
            // Action buttons row
            const Divider(color: Color(0xFF1E1C3A), height: 24),
            if (hasDecision) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'DECISION RECORDED: ${recordedAction!.toUpperCase()}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _loggedDecisions.remove(sub.id ?? sub.merchant);
                      });
                    },
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Undo',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.4),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildActionButton(sub, 'keep', const Color(0xFF6366F1)),
                  const SizedBox(width: 8),
                  _buildActionButton(sub, 'cancel', const Color(0xFFEF4444)),
                  const SizedBox(width: 8),
                  _buildActionButton(sub, 'ignore', Colors.grey),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDecisionStatusRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withOpacity(0.4),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(Subscription sub, String action, Color color) {
    return InkWell(
      onTap: () => _handleDecision(sub, action),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(
          action.toUpperCase(),
          style: TextStyle(
            color: color.withOpacity(0.8),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildDetailScreen() {
    final sub = _selectedSubscription!;
    final subSymbol = sub.price.currency == 'USD' ? '\$' : '¥';
    final accentColor = _getStatusColor(sub.status);
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _closeDetail,
        ),
        title: const Text('Details'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            // Big Merchant Logo Avatar
            Container(
              height: 80,
              width: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                sub.merchant[0].toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF6366F1),
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              sub.merchant,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                sub.status.toUpperCase(),
                style: TextStyle(
                  color: accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 30),
            // Billing detail card with Time Intelligence
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF121124),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF1E1C3A)),
              ),
              child: Column(
                children: [
                  _buildDetailRow('Estimated Price', '$subSymbol${sub.price.amount.toStringAsFixed(2)}'),
                  const Divider(color: Color(0xFF1E1C3A), height: 20),
                  _buildDetailRow('Currency', sub.price.currency),
                  const Divider(color: Color(0xFF1E1C3A), height: 20),
                  _buildDetailRow('Detection Confidence', '${(sub.confidence * 100).toInt()}%'),
                  const Divider(color: Color(0xFF1E1C3A), height: 20),
                  _buildDetailRow('First Invoice Date', sub.firstSeen ?? 'N/A'),
                  const Divider(color: Color(0xFF1E1C3A), height: 20),
                  _buildDetailRow('Latest Invoice Date', sub.lastSeen ?? 'N/A'),
                  const Divider(color: Color(0xFF1E1C3A), height: 20),
                  _buildDetailRow('Detected Cycle', sub.cycleDetected),
                  const Divider(color: Color(0xFF1E1C3A), height: 20),
                  _buildDetailRow('Stability Score', '${(sub.stabilityScore * 100).toInt()}%'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'DETECTION EVIDENCE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Color(0xFF10B981),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF121124),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: sub.evidence.map((ev) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.verified_outlined,
                          color: Color(0xFF10B981),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ev,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'BILLING HISTORY (EMAILS SCANNED)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: sub.history.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final email = sub.history[index];
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121124),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF1E1C3A)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                email.subject,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              email.date.length > 25 ? email.date.substring(0, 25) : email.date,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withOpacity(0.4),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          email.snippet,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            // Cancel instructions Action
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFFFCA5A5)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'To cancel this subscription, log in to your ${sub.merchant} account settings or look for "Billing" or "Subscriptions" pages.',
                      style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 14,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return const Color(0xFF10B981); // Emerald Green (Stable / 3+ cycles)
      case 'confirmed':
        return const Color(0xFF6366F1); // Indigo Blue (2 cycles)
      case 'detected':
        return const Color(0xFFF59E0B); // Amber Warning (1 cycle)
      case 'cancelled':
        return const Color(0xFFEF4444); // Red Danger (Emails stopped / old)
      default:
        return const Color(0xFF9CA3AF); // Grey Neutral (Unknown)
    }
  }
}
