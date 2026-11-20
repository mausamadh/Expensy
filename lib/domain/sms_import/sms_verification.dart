import 'dart:convert';

import 'iso4217.dart';
import 'sms_entities.dart';

class SmsVerification {
  final String id;
  final String inboxId;
  final String senderId;
  final String rawHash;
  final String body;
  final Map<String, dynamic> corrections;
  final String status;
  final int confirmationCount;
  final DateTime createdAt;
  final DateTime? appliedAt;

  SmsVerification({
    required this.id,
    required this.inboxId,
    required this.senderId,
    required this.rawHash,
    required this.body,
    required this.corrections,
    this.status = 'submitted',
    this.confirmationCount = 1,
    required this.createdAt,
    this.appliedAt,
  });

  String get correctionsJson => jsonEncode(corrections);

  Map<String, dynamic> toMap() => {
        'id': id,
        'inbox_id': inboxId,
        'sender_id': senderId,
        'raw_hash': rawHash,
        'body': body,
        'corrections_json': correctionsJson,
        'status': status,
        'confirmation_count': confirmationCount,
        'created_at': createdAt.toIso8601String(),
        'applied_at': appliedAt?.toIso8601String(),
      };

  static SmsVerification fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> corrections = const {};
    try {
      final decoded = jsonDecode((map['corrections_json'] as String?) ?? '{}');
      if (decoded is Map) {
        corrections =
            decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return SmsVerification(
      id: (map['id'] as String?) ?? '',
      inboxId: (map['inbox_id'] as String?) ?? '',
      senderId: (map['sender_id'] as String?) ?? '',
      rawHash: (map['raw_hash'] as String?) ?? '',
      body: (map['body'] as String?) ?? '',
      corrections: corrections,
      status: (map['status'] as String?) ?? 'submitted',
      confirmationCount: (map['confirmation_count'] as int?) ?? 1,
      createdAt: DateTime.tryParse((map['created_at'] as String?) ?? '') ??
          DateTime.now(),
      appliedAt: DateTime.tryParse((map['applied_at'] as String?) ?? ''),
    );
  }

  SmsVerification copyWith({
    String? status,
    int? confirmationCount,
    DateTime? appliedAt,
  }) =>
      SmsVerification(
        id: id,
        inboxId: inboxId,
        senderId: senderId,
        rawHash: rawHash,
        body: body,
        corrections: corrections,
        status: status ?? this.status,
        confirmationCount: confirmationCount ?? this.confirmationCount,
        createdAt: createdAt,
        appliedAt: appliedAt ?? this.appliedAt,
      );
}

class SmsLearningProposal {
  final String id;
  final String senderId;
  final String normalizedPattern;
  final Map<String, dynamic> corrections;
  final int confirmationCount;
  final int activationThreshold;
  final String status;
  final DateTime createdAt;
  final DateTime? activatedAt;

  SmsLearningProposal({
    required this.id,
    required this.senderId,
    required this.normalizedPattern,
    required this.corrections,
    this.confirmationCount = 1,
    this.activationThreshold = 3,
    this.status = 'draft',
    required this.createdAt,
    this.activatedAt,
  });

  bool get isSafeToActivate =>
      status == 'draft' &&
      confirmationCount >= activationThreshold &&
      !_usesUnsafeTransferCategory();

  bool _usesUnsafeTransferCategory() {
    final type = (corrections['type'] as String?)?.toLowerCase();
    final categoryId = corrections['categoryId'] as String?;
    if (type == 'transfer') {
      final source = corrections['accountId'] as String?;
      final destination = corrections['toAccountId'] as String?;
      return categoryId != 'sys_transfer' ||
          source == null ||
          destination == null ||
          source == destination;
    }
    return categoryId == 'sys_transfer';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'sender_id': senderId,
        'normalized_pattern': normalizedPattern,
        'corrections_json': jsonEncode(corrections),
        'confirmation_count': confirmationCount,
        'activation_threshold': activationThreshold,
        'status': status,
        'created_at': createdAt.toIso8601String(),
        'activated_at': activatedAt?.toIso8601String(),
      };

  static SmsLearningProposal fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> corrections = const {};
    try {
      final decoded = jsonDecode((map['corrections_json'] as String?) ?? '{}');
      if (decoded is Map) {
        corrections =
            decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return SmsLearningProposal(
      id: (map['id'] as String?) ?? '',
      senderId: (map['sender_id'] as String?) ?? '',
      normalizedPattern: (map['normalized_pattern'] as String?) ?? '',
      corrections: corrections,
      confirmationCount: (map['confirmation_count'] as int?) ?? 1,
      activationThreshold: (map['activation_threshold'] as int?) ?? 3,
      status: (map['status'] as String?) ?? 'draft',
      createdAt: DateTime.tryParse((map['created_at'] as String?) ?? '') ??
          DateTime.now(),
      activatedAt: DateTime.tryParse((map['activated_at'] as String?) ?? ''),
    );
  }
}

String normalizeSmsLearningPattern(String body) {
  var normalized = body.toLowerCase();
  normalized = normalized.replaceAll(
      RegExp(r'\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b'), '<DATE>');
  normalized =
      normalized.replaceAll(RegExp(r'\b\d+(?:[.,]\d+)*(?:\.\d+)?\b'), '<NUM>');
  normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
  return normalized;
}

class SmsLearningMatch {
  const SmsLearningMatch(this.proposal);
  final SmsLearningProposal proposal;
}

class SmsLearningMatcher {
  const SmsLearningMatcher();

  SmsLearningMatch? match(
    String senderId,
    String body,
    List<SmsLearningProposal> proposals,
  ) {
    final pattern = normalizeSmsLearningPattern(body);
    for (final proposal in proposals) {
      if (proposal.status == 'active' &&
          proposal.senderId == senderId &&
          proposal.normalizedPattern == pattern) {
        return SmsLearningMatch(proposal);
      }
    }
    return null;
  }

  SmsInboxItem apply(SmsInboxItem item, SmsLearningMatch match) {
    final corrections = match.proposal.corrections;
    final type = corrections['type'] as String?;
    final amount = corrections['amount'];
    final currency = corrections['currency'] as String?;
    final merchant = corrections['merchant'] as String?;
    final reference = corrections['reference'] as String?;
    final dateText = corrections['date'] as String?;

    int? minorUnits = item.parsedAmountMinorUnits;
    if (amount is num) {
      final exponent = currency == null ? 0 : Iso4217.exponentFor(currency);
      minorUnits = (amount * _powerOfTen(exponent)).round();
    }

    return item.copyWith(
      parsedType: type ?? item.parsedType,
      parsedAmountMinorUnits: minorUnits,
      parsedCurrency: currency ?? item.parsedCurrency,
      parsedMerchant: merchant ?? item.parsedMerchant,
      parsedReference: reference ?? item.parsedReference,
      parsedDate: dateText == null
          ? item.parsedDate
          : (DateTime.tryParse(dateText) ?? item.parsedDate),
      confidence: 'high',
      reviewReason: null,
    );
  }

  int _powerOfTen(int exponent) {
    var value = 1;
    for (var i = 0; i < exponent; i++) {
      value *= 10;
    }
    return value;
  }
}
