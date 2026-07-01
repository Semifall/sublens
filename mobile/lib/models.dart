class Subscription {
  final String id;
  final String userId;
  final String merchant;
  final String status; // unknown | detected | confirmed | active | canceled
  final double price;
  final String renewal; // monthly | yearly | one-time | unknown
  final String nextBilling; // YYYY-MM-DD
  final double confidence;
  final String createdAt;

  Subscription({
    required this.id,
    required this.userId,
    required this.merchant,
    required this.status,
    required this.price,
    required this.renewal,
    required this.nextBilling,
    required this.confidence,
    required this.createdAt,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      merchant: json['merchant'] as String? ?? 'Unknown Service',
      status: json['status'] as String? ?? 'unknown',
      price: (json['price'] as num? ?? 0.0).toDouble(),
      renewal: json['renewal'] as String? ?? 'monthly',
      nextBilling: json['next_billing'] as String? ?? '',
      confidence: (json['confidence'] as num? ?? 0.0).toDouble(),
      createdAt: json['created_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'merchant': merchant,
      'status': status,
      'price': price,
      'renewal': renewal,
      'next_billing': nextBilling,
      'confidence': confidence,
      'created_at': createdAt,
    };
  }
}

class Email {
  final String id;
  final String userId;
  final String gmailId;
  final String threadId;
  final String sender;
  final String subject;
  final String snippet;
  final String receivedAt;
  final String createdAt;

  Email({
    required this.id,
    required this.userId,
    required this.gmailId,
    required this.threadId,
    required this.sender,
    required this.subject,
    required this.snippet,
    required this.receivedAt,
    required this.createdAt,
  });

  factory Email.fromJson(Map<String, dynamic> json) {
    return Email(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      gmailId: json['gmail_id'] as String? ?? '',
      threadId: json['thread_id'] as String? ?? '',
      sender: json['sender'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      snippet: json['snippet'] as String? ?? '',
      receivedAt: json['received_at'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}
