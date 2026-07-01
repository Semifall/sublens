import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'api_client.dart';
import 'models.dart';
import 'localization.dart';

void main() {
  runApp(const SublensApp());
}

class SublensApp extends StatelessWidget {
  const SublensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SubLens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0C0A1C),
        primaryColor: const Color(0xFF6366F1),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const MainNavigationFrame(),
    );
  }
}

enum AppState {
  welcome,
  connectGmail,
  mainTabs,
  scanning
}

class MainNavigationFrame extends StatefulWidget {
  const MainNavigationFrame({super.key});

  @override
  State<MainNavigationFrame> createState() => _MainNavigationFrameState();
}

class _MainNavigationFrameState extends State<MainNavigationFrame> {
  AppState _appState = AppState.welcome;
  int _currentTab = 0; // 0: Home, 1: Subscriptions, 2: Scan (History), 3: Insights, 4: Settings
  String _currentLanguage = 'en'; // default English, toggleable to 'zh'

  // User Profile
  String _userEmail = "alex@gmail.com";
  String _userName = "Alex";

  // Data Stores
  List<Subscription> _subscriptions = [];
  double _monthlySpend = 0.0;
  int _activeCount = 0;
  List<dynamic> _scanHistory = [];
  Map<String, dynamic> _insightsData = {};
  
  // Scanning state
  String? _activeJobId;
  int _scanProgress = 0;
  int _scanEmailsScanned = 0;
  int _scanSubsFound = 0;
  String _scanTimeElapsed = "01:32";
  Timer? _scanTimer;

  // Navigation overlays
  Subscription? _selectedSubDetail;
  bool _showCancelGuide = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  // Fetch all data from API client
  Future<void> _loadAllData() async {
    try {
      final subRes = await ApiClient.getSubscriptions();
      final historyRes = await ApiClient.getScanHistory();
      final insightsRes = await ApiClient.getInsights();

      setState(() {
        _subscriptions = (subRes['subscriptions'] as List)
            .map((e) => Subscription.fromJson(e as Map<String, dynamic>))
            .toList();
        _monthlySpend = (subRes['monthly_spend'] as num).toDouble();
        _activeCount = subRes['active_count'] as int;
        _scanHistory = historyRes;
        _insightsData = insightsRes;
      });
    } catch (e) {
      debugPrint("Failed to load SubLens data: $e");
    }
  }

  // Auth login simulation
  Future<void> _handleGoogleLogin() async {
    try {
      await ApiClient.loginWithGoogle(_userEmail, _userName, "mock_google_oauth_token");
      await _loadAllData();
      setState(() {
        _appState = AppState.mainTabs;
        _currentTab = 0;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login failed: $e"), backgroundColor: Colors.red),
      );
    }
  }

  // Trigger new scan
  Future<void> _startScanFlow() async {
    try {
      setState(() {
        _appState = AppState.scanning;
        _scanProgress = 0;
        _scanEmailsScanned = 0;
        _scanSubsFound = 0;
      });

      final jobId = await ApiClient.startScan();
      _activeJobId = jobId;

      _scanTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) async {
        if (_activeJobId == null) {
          timer.cancel();
          return;
        }

        try {
          final status = await ApiClient.checkScanStatus(_activeJobId!);
          setState(() {
            _scanProgress = status['progress'] as int;
            _scanEmailsScanned = status['emails_scanned'] as int;
            _scanSubsFound = status['subscriptions_found'] as int;
            _scanTimeElapsed = status['time_elapsed'] as String;
          });

          if (status['status'] == 'done' || _scanProgress >= 100) {
            timer.cancel();
            _activeJobId = null;
            await _loadAllData();
            setState(() {
              _appState = AppState.mainTabs;
              _currentTab = 1; // Direct to Subscription List after scan completes
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Gmail subscription scan completed successfully!"),
                backgroundColor: Color(0xFF10B981),
              ),
            );
          }
        } catch (e) {
          timer.cancel();
          _activeJobId = null;
          setState(() {
            _appState = AppState.mainTabs;
          });
        }
      });
    } catch (e) {
      setState(() {
        _appState = AppState.mainTabs;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to trigger scan: $e")),
      );
    }
  }

  void _stopScan() {
    _scanTimer?.cancel();
    _activeJobId = null;
    setState(() {
      _appState = AppState.mainTabs;
    });
  }

  Future<void> _cancelSubscription(String id) async {
    try {
      await ApiClient.cancelSubscription(id);
      await _loadAllData();
      if (_selectedSubDetail != null && _selectedSubDetail!.id == id) {
        final updated = _subscriptions.firstWhere((element) => element.id == id);
        setState(() {
          _selectedSubDetail = updated;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Subscription marked as canceled.")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to cancel subscription: $e")),
      );
    }
  }

  void _logout() {
    ApiClient.jwtToken = null;
    setState(() {
      _appState = AppState.welcome;
      _subscriptions.clear();
      _monthlySpend = 0.0;
      _activeCount = 0;
      _selectedSubDetail = null;
      _showCancelGuide = false;
    });
  }

  AppLocalizations get local => AppLocalizations(_currentLanguage);

  @override
  Widget build(BuildContext context) {
    switch (_appState) {
      case AppState.welcome:
        return _buildWelcomeScreen();
      case AppState.connectGmail:
        return _buildConnectGmailScreen();
      case AppState.scanning:
        return _buildScanProgressScreen();
      case AppState.mainTabs:
        return _buildMainTabsFrame();
    }
  }

  // Screen 1: Welcome Screen
  Widget _buildWelcomeScreen() {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: 20),
              Column(
                children: [
                  // Premium SubLens logo placeholder
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'S',
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  Text(
                    local.translate('welcome_title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    local.translate('welcome_subtitle'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withOpacity(0.6),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _appState = AppState.connectGmail;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  local.translate('get_started'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Screen 2: Connect Gmail Screen
  Widget _buildConnectGmailScreen() {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            setState(() {
              _appState = AppState.welcome;
            });
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: 20),
              Column(
                children: [
                  // Gmail Logo Icon Card
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.mail_outline_rounded,
                        size: 36,
                        color: Colors.red.shade400,
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  Text(
                    local.translate('connect_title'),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    local.translate('connect_desc'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.5),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 16),
                        const SizedBox(width: 8),
                        Text(
                          local.translate('connect_badge'),
                          style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Column(
                children: [
                  ElevatedButton(
                    onPressed: _handleGoogleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0C0A1C),
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.g_mobiledata_rounded, size: 28, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          local.translate('continue_google'),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    local.translate('disconnect_anytime'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Screen 4: Scan Progress Screen
  Widget _buildScanProgressScreen() {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: 10),
              Column(
                children: [
                  Text(
                    local.translate('scanning_title'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    local.translate('scanning_desc'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
              // Circular progress indicator with custom percentage text
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 180,
                    height: 180,
                    child: CircularProgressIndicator(
                      value: _scanProgress / 100.0,
                      strokeWidth: 8,
                      backgroundColor: Colors.white.withOpacity(0.05),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_scanProgress%',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        local.translate('in_progress'),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.4),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Stats
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF16142E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.04)),
                ),
                child: Column(
                  children: [
                    _buildScanStatRow(local.translate('emails_scanned'), _scanEmailsScanned.toString()),
                    const Divider(color: Colors.white10, height: 24),
                    _buildScanStatRow(local.translate('subs_found'), _scanSubsFound.toString()),
                    const Divider(color: Colors.white10, height: 24),
                    _buildScanStatRow(local.translate('time_elapsed'), _scanTimeElapsed),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: _stopScan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444).withOpacity(0.1),
                  foregroundColor: const Color(0xFFFCA5A5),
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: const Color(0xFFEF4444).withOpacity(0.2)),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  local.translate('stop_scan'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScanStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
        ),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // Unified Frame hosting bottom tabs 0-4
  Widget _buildMainTabsFrame() {
    if (_selectedSubDetail != null) {
      return _showCancelGuide ? _buildCancelGuideScreen() : _buildSubscriptionDetailScreen();
    }

    return Scaffold(
      body: _buildCurrentTabBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (index) {
          setState(() {
            _currentTab = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF110F24),
        selectedItemColor: const Color(0xFF6366F1),
        unselectedItemColor: Colors.white.withOpacity(0.3),
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.credit_card_rounded), label: 'Subscriptions'),
          BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner_rounded), label: 'Scan'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded), label: 'Insights'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildCurrentTabBody() {
    switch (_currentTab) {
      case 0:
        return _buildDashboardScreen();
      case 1:
        return _buildSubscriptionsListScreen();
      case 2:
        return _buildScanHistoryScreen();
      case 3:
        return _buildInsightsScreen();
      case 4:
        return _buildSettingsScreen();
      default:
        return const SizedBox();
    }
  }

  // Screen 3: Dashboard (Home) Screen
  Widget _buildDashboardScreen() {
    final activeSubs = _subscriptions.where((element) => element.status == "active").take(3).toList();
    
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    local.translate('hello'),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    local.translate('overview'),
                    style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5)),
                  ),
                ],
              ),
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFF6366F1).withOpacity(0.2),
                child: const Text('A', style: TextStyle(color: Color(0xFF818CF8), fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 28),
          // Total Cards
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16142E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.04)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(local.translate('active_subs'), style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('$_activeCount', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('+2 this month', style: TextStyle(color: Colors.green, fontSize: 11)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16142E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.04)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(local.translate('monthly_spend'), style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('\$${_monthlySpend.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('+\$12.30 this month', style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                local.translate('recent_subs'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _currentTab = 1;
                  });
                },
                child: Text(local.translate('view_all'), style: const TextStyle(color: Color(0xFF818CF8))),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: activeSubs.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final sub = activeSubs[index];
              return _buildSubscriptionListTile(sub);
            },
          ),
          const SizedBox(height: 36),
          ElevatedButton(
            onPressed: _startScanFlow,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: Text(local.translate('start_new_scan'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Screen 5: Subscriptions List Screen
  Widget _buildSubscriptionsListScreen() {
    final activeSubs = _subscriptions.where((element) => element.status == "active").toList();
    final canceledSubs = _subscriptions.where((element) => element.status == "canceled").toList();
    
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(local.translate('your_subs'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: const Icon(Icons.filter_list_rounded, color: Colors.white70),
              onPressed: () {},
            ),
          ],
          bottom: TabBar(
            dividerColor: Colors.transparent,
            indicatorColor: const Color(0xFF6366F1),
            labelColor: const Color(0xFF818CF8),
            unselectedLabelColor: Colors.white.withOpacity(0.4),
            tabs: [
              Tab(text: '${local.translate('all')} (${_subscriptions.length})'),
              Tab(text: '${local.translate('active')} (${activeSubs.length})'),
              Tab(text: '${local.translate('canceled')} (${canceledSubs.length})'),
            ],
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: TabBarView(
            children: [
              _buildRawSubscriptionListView(_subscriptions),
              _buildRawSubscriptionListView(activeSubs),
              _buildRawSubscriptionListView(canceledSubs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRawSubscriptionListView(List<Subscription> list) {
    if (list.isEmpty) {
      return Center(
        child: Text(
          'No subscriptions found.',
          style: TextStyle(color: Colors.white.withOpacity(0.4)),
        ),
      );
    }
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final sub = list[index];
        return _buildSubscriptionListTile(sub);
      },
    );
  }

  Widget _buildSubscriptionListTile(Subscription sub) {
    final isCanceled = sub.status == "canceled";
    final badgeColor = isCanceled ? const Color(0xFFEF4444) : const Color(0xFF10B981);
    
    // Extract letter for avatar placeholder
    final letter = sub.merchant.isNotEmpty ? sub.merchant[0].toUpperCase() : 'S';
    
    return InkWell(
      onTap: () async {
        try {
          final detail = await ApiClient.getSubscriptionDetail(sub.id);
          setState(() {
            _selectedSubDetail = Subscription.fromJson(detail['subscription'] as Map<String, dynamic>);
          });
        } catch (e) {
          debugPrint("Detail load error: $e");
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF16142E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.03)),
        ),
        child: Row(
          children: [
            // Merchant Avatar
            CircleAvatar(
              radius: 20,
              backgroundColor: isCanceled ? const Color(0xFFEF4444).withOpacity(0.15) : const Color(0xFF6366F1).withOpacity(0.15),
              child: Text(
                letter,
                style: TextStyle(
                  color: isCanceled ? const Color(0xFFFCA5A5) : const Color(0xFF818CF8),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sub.merchant,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\$${sub.price.toStringAsFixed(2)} / ${sub.renewal}',
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: badgeColor.withOpacity(0.3)),
              ),
              child: Text(
                sub.status.toUpperCase(),
                style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Screen 6: Subscription Detail Screen
  Widget _buildSubscriptionDetailScreen() {
    final sub = _selectedSubDetail!;
    final isCanceled = sub.status == "canceled";
    final badgeColor = isCanceled ? const Color(0xFFEF4444) : const Color(0xFF10B981);
    final letter = sub.merchant.isNotEmpty ? sub.merchant[0].toUpperCase() : 'S';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            setState(() {
              _selectedSubDetail = null;
            });
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
        children: [
          Center(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: const Color(0xFF6366F1).withOpacity(0.15),
              child: Text(
                letter,
                style: const TextStyle(color: Color(0xFF818CF8), fontSize: 32, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              sub.merchant,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: badgeColor.withOpacity(0.3)),
              ),
              child: Text(
                sub.status.toUpperCase(),
                style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              '\$${sub.price.toStringAsFixed(2)} / month',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(height: 32),
          // Billing parameters
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF16142E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _buildDetailRow('Billing Cycle', sub.renewal.toUpperCase()),
                const Divider(color: Colors.white10, height: 24),
                _buildDetailRow('Next Charge', sub.nextBilling),
                const Divider(color: Colors.white10, height: 24),
                _buildDetailRow('Last Charge', 'Apr 15, 2024'),
                const Divider(color: Colors.white10, height: 24),
                _buildDetailRow('Detected In', 'Receipt from ${sub.merchant}'),
                const Divider(color: Colors.white10, height: 24),
                // Confidence bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Confidence Score', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    Row(
                      children: [
                        SizedBox(
                          width: 80,
                          height: 6,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: sub.confidence,
                              backgroundColor: Colors.white10,
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${(sub.confidence * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Text('Recent Emails (3)', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          // Mock recent emails list
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 3,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final dates = ["Apr 15, 2024", "Mar 15, 2024", "Feb 15, 2024"];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mail_outline, color: Colors.white30, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Receipt from ${sub.merchant}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 3),
                          Text(dates[index], style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 42),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _showCancelGuide = true;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.06),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cancel Guide', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: isCanceled ? null : () => _cancelSubscription(sub.id),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(isCanceled ? 'Canceled' : 'Mark as Canceled', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }

  // Screen 7: Cancel Guide Screen
  Widget _buildCancelGuideScreen() {
    final sub = _selectedSubDetail!;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('How to cancel ${sub.merchant}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            setState(() {
              _showCancelGuide = false;
            });
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGuideStep('1', 'Go to ${sub.merchant} Account', 'Visit ${sub.merchant.toLowerCase().replaceFirst(' ', '')}.com and sign in to your account.'),
                const SizedBox(height: 24),
                _buildGuideStep('2', 'Go to Billing', 'Click on your profile icon > Account > Billing Details.'),
                const SizedBox(height: 24),
                _buildGuideStep('3', 'Cancel Membership', 'Click \'Cancel Membership\' and follow the confirmation steps.'),
                const SizedBox(height: 24),
                _buildGuideStep('4', 'Confirmation', 'You\'ll receive a confirmation email after cancellation.'),
              ],
            ),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text('Open ${sub.merchant} Account', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideStep(String num, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFF6366F1).withOpacity(0.15),
          child: Text(
            num,
            style: const TextStyle(color: Color(0xFF818CF8), fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(desc, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }

  // Screen 8: Scan History Screen
  Widget _buildScanHistoryScreen() {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Scan History', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(20.0),
        itemCount: _scanHistory.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final scan = _scanHistory[index];
          final completed = scan['status'] == "Completed";
          
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF16142E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(scan['date'] as String, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(
                      '${scan['emails_scanned']} emails scanned • ${scan['subscriptions_found']} subscriptions found',
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: completed ? const Color(0xFF10B981).withOpacity(0.1) : const Color(0xFFEF4444).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: completed ? const Color(0xFF10B981).withOpacity(0.3) : const Color(0xFFEF4444).withOpacity(0.3)),
                  ),
                  child: Text(
                    (scan['status'] as String).toUpperCase(),
                    style: TextStyle(color: completed ? const Color(0xFF10B981) : const Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Screen 9: Insights Screen
  Widget _buildInsightsScreen() {
    final Map<String, dynamic> categories = _insightsData['categories'] as Map<String, dynamic>? ?? {
      "Entertainment": 31.97,
      "Productivity": 60.99,
      "Music": 9.99,
      "Other": 5.00
    };
    
    final List<dynamic> spendTrend = _insightsData['spend_trend'] as List<dynamic>? ?? [
      {"month": "Dec", "amount": 112.50},
      {"month": "Jan", "amount": 120.00},
      {"month": "Feb", "amount": 120.00},
      {"month": "Mar", "amount": 134.48},
      {"month": "Apr", "amount": 134.48},
      {"month": "May", "amount": 142.47}
    ];

    final double totalSaved = (_insightsData['total_saved'] as num? ?? 24.50).toDouble();
    final int canceledCount = _insightsData['canceled_count'] as int? ?? 2;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Insights', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF16142E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Monthly Spend Trend', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 6),
                Row(
                  children: const [
                    Text('\$142.47', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                    SizedBox(width: 8),
                    Text('+\$12.39 (9.4%)', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 20),
                // Spend trend custom painter line chart
                SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: SpendTrendLineChartPainter(spendTrend: spendTrend),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Top Categories ring chart card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF16142E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Top Categories', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    SizedBox(
                      width: 110,
                      height: 110,
                      child: CustomPaint(
                        painter: CategoryRingChartPainter(categories: categories),
                      ),
                    ),
                    const SizedBox(width: 28),
                    Expanded(
                      child: Column(
                        children: [
                          _buildCategoryLegendItem('Entertainment', '\$${categories["Entertainment"]}', const Color(0xFFEC4899)),
                          const SizedBox(height: 8),
                          _buildCategoryLegendItem('Productivity', '\$${categories["Productivity"]}', const Color(0xFF3B82F6)),
                          const SizedBox(height: 8),
                          _buildCategoryLegendItem('Music', '\$${categories["Music"]}', const Color(0xFF10B981)),
                          const SizedBox(height: 8),
                          _buildCategoryLegendItem('Other', '\$${categories["Other"]}', const Color(0xFFF59E0B)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Quick stats
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16142E),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Saved', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 8),
                      Text('\$${totalSaved.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF10B981), fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('This month', style: TextStyle(color: Colors.white24, fontSize: 10)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16142E),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Canceled', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 8),
                      Text('$canceledCount', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('This month', style: TextStyle(color: Colors.white24, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryLegendItem(String title, String val, Color col) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        Text(val, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // Screen 10: Settings Screen
  Widget _buildSettingsScreen() {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(local.translate('settings'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          Text(local.translate('account'), style: const TextStyle(color: Colors.white30, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF16142E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.mail_outline_rounded, color: Colors.redAccent, size: 22),
                    SizedBox(width: 12),
                    Text('Connected Gmail', style: TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
                Text(_userEmail, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(local.translate('preferences'), style: const TextStyle(color: Colors.white30, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF16142E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _buildSettingsPreferenceRow(local.translate('scan_freq'), 'Weekly'),
                const Divider(color: Colors.white10, height: 24),
                _buildSettingsPreferenceRow(local.translate('sync_range'), 'All time'),
                const Divider(color: Colors.white10, height: 24),
                _buildSettingsPreferenceRow(local.translate('currency'), 'USD (\$)'),
                const Divider(color: Colors.white10, height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(local.translate('language'), style: const TextStyle(color: Colors.white, fontSize: 13)),
                    DropdownButton<String>(
                      value: _currentLanguage,
                      dropdownColor: const Color(0xFF16142E),
                      underline: const SizedBox(),
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                      style: const TextStyle(color: Color(0xFF818CF8), fontSize: 13, fontWeight: FontWeight.bold),
                      items: const [
                        DropdownMenuItem(value: 'en', child: Text('English')),
                        DropdownMenuItem(value: 'zh', child: Text('简体中文')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _currentLanguage = val;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(local.translate('support'), style: const TextStyle(color: Colors.white30, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF16142E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _buildSettingsLinkRow(local.translate('help_center')),
                const Divider(color: Colors.white10, height: 24),
                _buildSettingsLinkRow(local.translate('contact_us')),
                const Divider(color: Colors.white10, height: 24),
                _buildSettingsLinkRow(local.translate('privacy')),
                const Divider(color: Colors.white10, height: 24),
                _buildSettingsLinkRow(local.translate('terms')),
              ],
            ),
          ),
          const SizedBox(height: 42),
          TextButton(
            onPressed: _logout,
            child: Text(
              local.translate('log_out'),
              style: const TextStyle(color: Colors.redAccent, fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsPreferenceRow(String label, String val) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
        Row(
          children: [
            Text(val, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 12),
          ],
        ),
      ],
    );
  }

  Widget _buildSettingsLinkRow(String label) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 12),
      ],
    );
  }
}

// Custom painter for Spend Trend Line Chart (Screen 9)
class SpendTrendLineChartPainter extends CustomPainter {
  final List<dynamic> spendTrend;

  SpendTrendLineChartPainter({required this.spendTrend});

  @override
  void paint(Canvas canvas, Size size) {
    if (spendTrend.isEmpty) return;

    final paintLine = Paint()
      ..color = const Color(0xFF6366F1)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final paintFill = Paint()
      ..style = PaintingStyle.fill;

    final double widthBetweenPoints = size.width / (spendTrend.length - 1);
    
    // Find min/max values
    double minVal = double.infinity;
    double maxVal = -double.infinity;
    for (var pt in spendTrend) {
      final double amt = (pt['amount'] as num).toDouble();
      if (amt < minVal) minVal = amt;
      if (amt > maxVal) maxVal = amt;
    }

    // Add extra padding to min/max to prevent line touching top/bottom
    minVal -= 5;
    maxVal += 5;
    final double range = maxVal - minVal;

    final List<Offset> points = [];
    for (int i = 0; i < spendTrend.length; i++) {
      final double amt = (spendTrend[i]['amount'] as num).toDouble();
      final double x = i * widthBetweenPoints;
      final double y = size.height - ((amt - minVal) / range) * size.height;
      points.add(Offset(x, y));
    }

    // Draw background gradient fill under line
    final pathFill = Path();
    pathFill.moveTo(0, size.height);
    for (var pt in points) {
      pathFill.lineTo(pt.dx, pt.dy);
    }
    pathFill.lineTo(size.width, size.height);
    pathFill.close();

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF6366F1).withOpacity(0.2),
        const Color(0xFF6366F1).withOpacity(0.0),
      ],
    );
    paintFill.shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(pathFill, paintFill);

    // Draw the main line path
    final pathLine = Path();
    pathLine.moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      pathLine.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(pathLine, paintLine);

    // Draw glowing circles on points
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final dotOuterPaint = Paint()
      ..color = const Color(0xFF6366F1)
      ..style = PaintingStyle.fill;

    for (var pt in points) {
      canvas.drawCircle(pt, 5, dotOuterPaint);
      canvas.drawCircle(pt, 2.5, dotPaint);
    }

    // Draw text labels for months under points
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < spendTrend.length; i++) {
      final String month = spendTrend[i]['month'] as String;
      textPainter.text = TextSpan(
        text: month,
        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(points[i].dx - textPainter.width / 2, size.height - 14),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Custom painter for Doughnut / Ring Chart (Screen 9)
class CategoryRingChartPainter extends CustomPainter {
  final Map<String, dynamic> categories;

  CategoryRingChartPainter({required this.categories});

  @override
  void paint(Canvas canvas, Size size) {
    final double total = categories.values.fold(0.0, (sum, item) => sum + (item as num).toDouble());
    if (total == 0.0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2);
    const strokeWidth = 14.0;

    final paintArc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final colors = [
      const Color(0xFFEC4899), // Entertainment
      const Color(0xFF3B82F6), // Productivity
      const Color(0xFF10B981), // Music
      const Color(0xFFF59E0B), // Other
    ];

    final keys = ["Entertainment", "Productivity", "Music", "Other"];
    double startAngle = -pi / 2;

    for (int i = 0; i < keys.length; i++) {
      final val = (categories[keys[i]] as num? ?? 0.0).toDouble();
      if (val == 0.0) continue;
      
      final sweepAngle = (val / total) * 2 * pi;
      paintArc.color = colors[i];
      
      // Draw slightly padded arc to show segment divisions nicely
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        startAngle + 0.04,
        sweepAngle - 0.08,
        false,
        paintArc,
      );
      
      startAngle += sweepAngle;
    }

    // Draw total text in the center
    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.text = TextSpan(
      text: 'Total\n\$${total.toStringAsFixed(0)}',
      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, height: 1.3),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
