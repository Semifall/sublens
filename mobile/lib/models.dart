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

class Subscription {
  final String? id;
  final String merchant;
  final Money price;
  final String status;
  final double confidence;

  Subscription({
    this.id,
    required this.merchant,
    required this.price,
    required this.status,
    required this.confidence,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      id: json['id'] as String?,
      merchant: json['merchant'] as String,
      price: Money.fromJson(json['price'] as Map<String, dynamic>),
      status: json['status'] as String,
      confidence: (json['confidence'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'merchant': merchant,
      'price': price.toJson(),
      'status': status,
      'confidence': confidence,
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
