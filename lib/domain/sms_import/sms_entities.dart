// Domain entities for the SMS import context.
//
// Pure Dart — no Flutter, plugin, or database imports (enforced by
// tool/ci_guard.dart). These classes were extracted from
// lib/models/models.dart so the domain layer owns its own vocabulary.
// models.dart re-exports them for existing import sites.

/// A raw SMS message as captured by the device.
///
/// Domain-owned value object: the plugin's `SmsMessage` type is forbidden
/// in the domain, so adapters map plugin messages into this shape before
/// anything crosses the port boundary.
class SmsMessage {
  final String id;
  final String sender;
  final String body;

  /// Epoch millis (0 if unknown).
  final int timestamp;

  const SmsMessage({
    required this.id,
    required this.sender,
    required this.body,
    this.timestamp = 0,
  });

  DateTime get dateTime => timestamp > 0
      ? DateTime.fromMillisecondsSinceEpoch(timestamp)
      : DateTime.now();
}

/// A sender (phone number / address) with the count of messages seen.
class SmsSender {
  final String sender;
  final int count;

  const SmsSender({required this.sender, required this.count});
}

/// SMS permission state reported by the platform.
class SmsPermissions {
  final bool read;
  final bool receive;
  final bool isDefaultSmsApp;

  const SmsPermissions({
    required this.read,
    required this.receive,
    required this.isDefaultSmsApp,
  });

  bool get canScan => read || isDefaultSmsApp;
}

/// A parsed (or unparseable) SMS surfaced in the inbox for user review.
class SmsInboxItem {
  final String id;
  final String senderId;
  final String body;
  final String rawHash;
  final int smsTimestamp; // epoch millis (0 if unknown)
  // Parsed fields (null when the parser produced no match).
  final String? parsedType;
  final int? parsedAmountMinorUnits;
  final String? parsedCurrency;
  final String? parsedMerchant;
  final String? parsedReference;
  final DateTime? parsedDate;
  final String? confidence;
  final String? reviewReason;
  final String? templateId;
  String status; // pending | imported | dismissed
  final String? importedTxId;
  final DateTime createdAt;

  SmsInboxItem({
    required this.id,
    required this.senderId,
    required this.body,
    required this.rawHash,
    this.smsTimestamp = 0,
    this.parsedType,
    this.parsedAmountMinorUnits,
    this.parsedCurrency,
    this.parsedMerchant,
    this.parsedReference,
    this.parsedDate,
    this.confidence,
    this.reviewReason,
    this.templateId,
    this.status = 'pending',
    this.importedTxId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'sender_id': senderId,
        'body': body,
        'raw_hash': rawHash,
        'sms_timestamp': smsTimestamp,
        'parsed_type': parsedType,
        'parsed_amount_minor_units': parsedAmountMinorUnits,
        'parsed_currency': parsedCurrency,
        'parsed_merchant': parsedMerchant,
        'parsed_reference': parsedReference,
        'parsed_date': parsedDate?.toIso8601String(),
        'confidence': confidence,
        'review_reason': reviewReason,
        'template_id': templateId,
        'status': status,
        'imported_tx_id': importedTxId,
        'created_at': createdAt.toIso8601String(),
      };

  static SmsInboxItem fromMap(Map<String, dynamic> m) => SmsInboxItem(
        id: (m['id'] as String?) ?? '',
        senderId: (m['sender_id'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
        rawHash: (m['raw_hash'] as String?) ?? '',
        smsTimestamp: (m['sms_timestamp'] as int?) ?? 0,
        parsedType: m['parsed_type'] as String?,
        parsedAmountMinorUnits: m['parsed_amount_minor_units'] as int?,
        parsedCurrency: m['parsed_currency'] as String?,
        parsedMerchant: m['parsed_merchant'] as String?,
        parsedReference: m['parsed_reference'] as String?,
        parsedDate: m['parsed_date'] != null
            ? DateTime.parse(m['parsed_date'] as String)
            : null,
        confidence: m['confidence'] as String?,
        reviewReason: m['review_reason'] as String?,
        templateId: m['template_id'] as String?,
        status: (m['status'] as String?) ?? 'pending',
        importedTxId: m['imported_tx_id'] as String?,
        createdAt: m['created_at'] != null
            ? DateTime.parse(m['created_at'] as String)
            : DateTime.now(),
      );

  SmsInboxItem copyWith({
    String? status,
    String? importedTxId,
    String? parsedType,
    int? parsedAmountMinorUnits,
    String? parsedCurrency,
    String? parsedMerchant,
    String? parsedReference,
    DateTime? parsedDate,
    String? confidence,
    String? reviewReason,
    String? templateId,
  }) =>
      SmsInboxItem(
        id: id,
        senderId: senderId,
        body: body,
        rawHash: rawHash,
        smsTimestamp: smsTimestamp,
        parsedType: parsedType ?? this.parsedType,
        parsedAmountMinorUnits:
            parsedAmountMinorUnits ?? this.parsedAmountMinorUnits,
        parsedCurrency: parsedCurrency ?? this.parsedCurrency,
        parsedMerchant: parsedMerchant ?? this.parsedMerchant,
        parsedReference: parsedReference ?? this.parsedReference,
        parsedDate: parsedDate ?? this.parsedDate,
        confidence: confidence ?? this.confidence,
        reviewReason: reviewReason ?? this.reviewReason,
        templateId: templateId ?? this.templateId,
        status: status ?? this.status,
        importedTxId: importedTxId ?? this.importedTxId,
        createdAt: createdAt,
      );
}

/// Per-sender SMS parsing preferences. A sender (e.g. a bank) can send
/// transactional, OTP, promotional and personal messages — so instead of
/// blocking the whole sender, the user can (a) allow/deny parsing for the
/// sender entirely and (b) suppress specific message kinds they have
/// acknowledged ("don't show again").
class SmsSenderPref {
  final String id;
  final String senderId;

  /// Whether messages from this sender are parsed/surfaced at all.
  final bool parseAllowed;

  /// Message kinds the user has acknowledged and wants hidden, e.g.
  /// `{SmsKind.otp, SmsKind.promotional}`.
  final Set<String> suppressedKinds;
  final DateTime createdAt;

  SmsSenderPref({
    required this.id,
    required this.senderId,
    this.parseAllowed = true,
    Set<String>? suppressedKinds,
    DateTime? createdAt,
  })  : suppressedKinds = suppressedKinds ?? <String>{},
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'sender_id': senderId,
        'parse_allowed': parseAllowed ? 1 : 0,
        'suppressed_kinds': suppressedKinds.join(','),
        'created_at': createdAt.toIso8601String(),
      };

  static SmsSenderPref fromMap(Map<String, dynamic> m) => SmsSenderPref(
        id: (m['id'] as String?) ?? '',
        senderId: (m['sender_id'] as String?) ?? '',
        parseAllowed: (m['parse_allowed'] as int? ?? 1) != 0,
        suppressedKinds: (m['suppressed_kinds'] as String? ?? '')
            .split(',')
            .where((k) => k.trim().isNotEmpty)
            .map((k) => k.trim())
            .toSet(),
        createdAt: m['created_at'] != null
            ? DateTime.parse(m['created_at'] as String)
            : DateTime.now(),
      );

  SmsSenderPref copyWith({
    bool? parseAllowed,
    Set<String>? suppressedKinds,
  }) =>
      SmsSenderPref(
        id: id,
        senderId: senderId,
        parseAllowed: parseAllowed ?? this.parseAllowed,
        suppressedKinds: suppressedKinds ?? this.suppressedKinds,
        createdAt: createdAt,
      );
}

/// A user-confirmed routing rule: when an SMS from [senderId] (optionally
/// matching [merchantPattern]) is imported, use these account/category/type.
class SmsRule {
  final String id;
  final String senderId;
  final String? merchantPattern;
  final String accountId;
  final String categoryId;
  final String transactionType; // income | expense | transfer
  final DateTime createdAt;

  SmsRule({
    required this.id,
    required this.senderId,
    this.merchantPattern,
    required this.accountId,
    required this.categoryId,
    required this.transactionType,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'sender_id': senderId,
        'merchant_pattern': merchantPattern,
        'account_id': accountId,
        'category_id': categoryId,
        'transaction_type': transactionType,
        'created_at': createdAt.toIso8601String(),
      };

  static SmsRule fromMap(Map<String, dynamic> m) => SmsRule(
        id: (m['id'] as String?) ?? '',
        senderId: (m['sender_id'] as String?) ?? '',
        merchantPattern: m['merchant_pattern'] as String?,
        accountId: (m['account_id'] as String?) ?? '',
        categoryId: (m['category_id'] as String?) ?? '',
        transactionType: (m['transaction_type'] as String?) ?? 'expense',
        createdAt: m['created_at'] != null
            ? DateTime.parse(m['created_at'] as String)
            : DateTime.now(),
      );
}

/// A first-parsed account suggestion derived from SMS senders and content.
class SmsAccountSuggestion {
  final String name;
  final String type; // bank | savings | debit | credit | wallet
  final String senderId;
  final int evidenceCount;

  const SmsAccountSuggestion({
    required this.name,
    required this.type,
    required this.senderId,
    required this.evidenceCount,
  });
}
