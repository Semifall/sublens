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
  
  // API Data
  ScanSummary? _summary;
  List<Subscription> _subscriptions = [];
  Subscription? _selectedSubscription;
  String? _errorMsg;

  // Initiates the scan flow
  Future<void> _startScanFlow() async {
    setState(() {
      _currentState = AppState.scanning;
      _scanProgressPct = 0;
      _scanProgressText = "Connecting to Google Account...";
      _errorMsg = null;
    });

    try {
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

            setState(() {
              _subscriptions = subsJson
                  .map((s) => Subscription.fromJson(s as Map<String, dynamic>))
                  .toList();
              _summary = ScanSummary.fromJson(summaryJson);
              _currentState = AppState.dashboard;
            });
          } else if (status == 'failed') {
            timer.cancel();
            setState(() {
              _errorMsg = "Scanning process failed on the server.";
              _currentState = AppState.auth;
            });
          }
        } catch (e) {
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
    setState(() {
      _subscriptions = [];
      _summary = null;
      _currentState = AppState.auth;
    });
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
            // Cost Leakage Summary Card
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
                    'Annual Subscription Leakage',
                    style: TextStyle(
                      color: Color(0xFFC7D2FE),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$currencySymbol${_summary?.yearlyCost.toStringAsFixed(2) ?? "0.00"}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSummaryStat(
                        'Monthly Cost',
                        '$currencySymbol${_summary?.monthlyCost.toStringAsFixed(2) ?? "0.00"}',
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
        child: Row(
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
                      // Confidence percentage
                      Text(
                        '${(sub.confidence * 100).toInt()}% Match',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.4),
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
            const SizedBox(height: 40),
            // Billing detail card
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
                  const Divider(color: Color(0xFF1E1C3A), height: 30),
                  _buildDetailRow('Currency', sub.price.currency),
                  const Divider(color: Color(0xFF1E1C3A), height: 30),
                  _buildDetailRow('Detection Confidence', '${(sub.confidence * 100).toInt()}%'),
                ],
              ),
            ),
            const Spacer(),
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
            const SizedBox(height: 24),
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
        return const Color(0xFF10B981); // Emerald Green
      case 'trial':
        return const Color(0xFFF59E0B); // Amber Warning
      case 'price_changed':
        return const Color(0xFF3B82F6); // Blue Informative
      case 'cancelled':
        return const Color(0xFFEF4444); // Red Danger
      default:
        return const Color(0xFF9CA3AF); // Grey Neutral
    }
  }
}
