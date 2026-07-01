class Money {
  final double amount;
  final String currency;

  Money({required this.amount, required this.currency});

  factory Money.fromJson(Map<String, dynamic> json) {
    return Money(
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'amount': amount,
      'currency': currency,
    };
  }
}

class Email {
  final String id;
  final String subject;
  final String sender;
  final String snippet;
  final String date;

  Email({
    required this.id,
    required this.subject,
    required this.sender,
    required this.snippet,
    required this.date,
  });

  factory Email.fromJson(Map<String, dynamic> json) {
    return Email(
      id: json['id'] as String,
      subject: json['subject'] as String,
      sender: json['sender'] as String,
      snippet: json['snippet'] as String,
      date: json['date'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'subject': subject,
      'sender': sender,
      'snippet': snippet,
      'date': date,
    };
  }
}

class Subscription {
  final String? id;
  final String merchant;
  final Money price;
  final String status;
  final double confidence;
  final String? lastSeenEmailId;
  final List<Email> history;
  final List<String> evidence;
  final String? firstSeen;
  final String? lastSeen;
  final String cycleDetected;
  final double stabilityScore;

  Subscription({
    this.id,
    required this.merchant,
    required this.price,
    required this.status,
    required this.confidence,
    this.lastSeenEmailId,
    required this.history,
    required this.evidence,
    this.firstSeen,
    this.lastSeen,
    required this.cycleDetected,
    required this.stabilityScore,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) {
    var historyList = json['history'] as List<dynamic>? ?? [];
    List<Email> historyEmails = historyList
        .map((e) => Email.fromJson(e as Map<String, dynamic>))
        .toList();
        
    var evidenceList = json['evidence'] as List<dynamic>? ?? [];
    List<String> evidenceStrings = evidenceList.map((e) => e as String).toList();

    return Subscription(
      id: json['id'] as String?,
      merchant: json['merchant'] as String,
      price: Money.fromJson(json['price'] as Map<String, dynamic>),
      status: json['status'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      lastSeenEmailId: json['last_seen_email_id'] as String?,
      history: historyEmails,
      evidence: evidenceStrings,
      firstSeen: json['first_seen'] as String?,
      lastSeen: json['last_seen'] as String?,
      cycleDetected: json['cycle_detected'] as String? ?? "monthly",
      stabilityScore: (json['stability_score'] as num? ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'merchant': merchant,
      'price': price.toJson(),
      'status': status,
      'confidence': confidence,
      'last_seen_email_id': lastSeenEmailId,
      'history': history.map((e) => e.toJson()).toList(),
      'evidence': evidence,
      'first_seen': firstSeen,
      'last_seen': lastSeen,
      'cycle_detected': cycleDetected,
      'stability_score': stabilityScore,
    };
  }
}

class ScanSummary {
  final double monthlyCost;
  final double yearlyCost;
  final int subscriptionCount;

  ScanSummary({
    required this.monthlyCost,
    required this.yearlyCost,
    required this.subscriptionCount,
  });

  factory ScanSummary.fromJson(Map<String, dynamic> json) {
    return ScanSummary(
      monthlyCost: (json['monthly_cost'] as num).toDouble(),
      yearlyCost: (json['yearly_cost'] as num).toDouble(),
      subscriptionCount: json['subscription_count'] as int,
    );
  }
}
