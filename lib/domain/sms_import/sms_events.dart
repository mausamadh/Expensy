import 'dart:convert';

enum SmsOutboxStatus {
  queued,
  processing,
  completed,
  deadLetter,
}

extension SmsOutboxStatusName on SmsOutboxStatus {
  static SmsOutboxStatus fromName(String name) {
    switch (name) {
      case 'processing':
        return SmsOutboxStatus.processing;
      case 'completed':
        return SmsOutboxStatus.completed;
      case 'dead_letter':
        return SmsOutboxStatus.deadLetter;
      case 'queued':
      default:
        return SmsOutboxStatus.queued;
    }
  }

  String get name {
    switch (this) {
      case SmsOutboxStatus.processing:
        return 'processing';
      case SmsOutboxStatus.completed:
        return 'completed';
      case SmsOutboxStatus.deadLetter:
        return 'dead_letter';
      case SmsOutboxStatus.queued:
        return 'queued';
    }
  }
}

class SmsDomainEventNames {
  static const received = 'sms.received';
  static const parseRequested = 'sms.parse_requested';
  static const parseCompleted = 'sms.parse_completed';
  static const verificationRequested = 'sms.verification_requested';
  static const verificationSubmitted = 'sms.verification_submitted';
  static const verificationApplied = 'sms.verification_applied';
  static const templateLearned = 'sms.template_learned';
  static const importRequested = 'sms.import_requested';
  static const imported = 'sms.imported';
  static const importFailed = 'sms.import_failed';
  static const notificationRequested = 'sms.notification_requested';
}

class SmsOutboxEvent {
  final String id;
  final String eventType;
  final String aggregateId;
  final String idempotencyKey;
  final Map<String, dynamic> payload;
  final SmsOutboxStatus status;
  final int attemptCount;
  final DateTime availableAt;
  final DateTime createdAt;
  final DateTime? processedAt;
  final String? lastError;

  SmsOutboxEvent({
    required this.id,
    required this.eventType,
    required this.aggregateId,
    required this.idempotencyKey,
    required this.payload,
    this.status = SmsOutboxStatus.queued,
    this.attemptCount = 0,
    required this.availableAt,
    required this.createdAt,
    this.processedAt,
    this.lastError,
  });

  String get payloadJson => jsonEncode(payload);

  Map<String, dynamic> toMap() => {
        'id': id,
        'event_type': eventType,
        'aggregate_id': aggregateId,
        'idempotency_key': idempotencyKey,
        'payload_json': payloadJson,
        'status': status.name,
        'attempt_count': attemptCount,
        'available_at': availableAt.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'processed_at': processedAt?.toIso8601String(),
        'last_error': lastError,
      };

  static SmsOutboxEvent fromMap(Map<String, dynamic> map) {
    final payloadText = (map['payload_json'] as String? ?? '{}').trim();
    Map<String, dynamic> decoded = const {};
    try {
      final value = jsonDecode(payloadText);
      if (value is Map) {
        decoded = value.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}

    DateTime? nullableDate(String key) {
      final value = map[key] as String?;
      return value == null || value.isEmpty ? null : DateTime.tryParse(value);
    }

    return SmsOutboxEvent(
      id: (map['id'] as String?) ?? '',
      eventType: (map['event_type'] as String?) ?? '',
      aggregateId: (map['aggregate_id'] as String?) ?? '',
      idempotencyKey: (map['idempotency_key'] as String?) ?? '',
      payload: decoded,
      status:
          SmsOutboxStatusName.fromName((map['status'] as String?) ?? 'queued'),
      attemptCount: (map['attempt_count'] as int?) ?? 0,
      availableAt: nullableDate('available_at') ??
          nullableDate('created_at') ??
          DateTime.now(),
      createdAt: nullableDate('created_at') ?? DateTime.now(),
      processedAt: nullableDate('processed_at'),
      lastError: map['last_error'] as String?,
    );
  }
}
