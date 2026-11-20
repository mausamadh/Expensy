// Ports for the SMS import context (hexagonal architecture).
//
// Domain-owned interfaces: the application layer programs against these,
// and adapters (lib/adapters/sms/) provide the concrete implementations.
// No Flutter, plugin, or database imports allowed here (ci_guard).

import 'dart:async';

import '../sms_entities.dart';
import '../template_registry.dart';
import '../sms_events.dart';
import '../sms_verification.dart';

/// Loads the [TemplateRegistry] (built-in + user templates).
///
/// The concrete loader reads from asset bundles (Flutter), so it lives in an
/// adapter; the domain and application layers only see this port.
abstract interface class TemplateRegistryProvider {
  Future<TemplateRegistry> load();
}

/// Source of raw SMS messages from the device.
///
/// Implemented by [ExpensySmsSource] (lib/adapters/sms/) which wraps the
/// `expensy_sms` plugin and maps plugin types into domain types.
abstract interface class SmsSource {
  /// Scans up to [limit] recent inbox messages, newest first.
  Future<List<SmsMessage>> scanSms({int limit = 500});

  /// Distinct senders with message counts (for the sender picker).
  Future<List<SmsSender>> getSenders();

  /// Current SMS permission state.
  Future<SmsPermissions> checkPermissions();

  /// Requests SMS permissions from the platform.
  Future<SmsPermissions> requestPermissions();

  /// Starts live capture; emits each newly received message.
  Stream<SmsMessage> startLiveCapture();

  /// Stops live capture.
  Future<void> stopLiveCapture();
}

/// Persistence for the SMS inbox (pending/imported/dismissed candidates).
abstract interface class SmsInboxRepository {
  /// All inbox items, newest first.
  Future<List<SmsInboxItem>> getAll();

  /// Items with the given status, newest first.
  Future<List<SmsInboxItem>> getByStatus(String status);

  /// Looks up an item by its raw hash (dedup key).
  Future<SmsInboxItem?> getByHash(String rawHash);

  Future<void> insert(SmsInboxItem item);

  Future<void> update(SmsInboxItem item);

  Future<void> delete(String id);
}

/// Persistence for user-confirmed routing rules.
abstract interface class SmsRuleRepository {
  Future<List<SmsRule>> getAll();

  Future<void> insert(SmsRule rule);

  Future<void> update(SmsRule rule);

  Future<void> delete(String id);
}

/// Persistence for per-sender parsing preferences.
abstract interface class SmsSenderPrefRepository {
  Future<List<SmsSenderPref>> getAll();

  Future<void> insert(SmsSenderPref pref);

  Future<void> update(SmsSenderPref pref);

  Future<void> delete(String id);
}

/// Persistence for SMS import settings (currently: global OTP auto-hide).
abstract interface class SmsSettings {
  /// Whether OTP messages are hidden globally without per-sender
  /// acknowledgement. Default true.
  Future<bool> getAutoHideOtp();

  Future<void> setAutoHideOtp(bool value);

  Future<bool> getLiveCaptureEnabled();
  Future<void> setLiveCaptureEnabled(bool value);
}

/// Writes ledger transactions from the SMS import context.
///
/// The SMS context must not reach into the ledger's internals; it asks
/// this port to record a transaction. Implemented by an adapter over
/// AppProvider until the ledger context is migrated (Phase 2).
abstract interface class LedgerGateway {
  /// Records an income/expense transaction. Returns the created
  /// transaction id, or null if it could not be recorded.
  Future<String?> addTransaction({
    required String id,
    required String type, // 'income' | 'expense'
    required double amount,
    required String description,
    required String accountId,
    required String categoryId,
    required DateTime date,
    String? note,
  });

  /// Records a transfer between two accounts. Returns the debit leg's
  /// transaction id, or null if it could not be recorded.
  Future<String?> addTransfer({
    required String fromId,
    required String toId,
    required double fromAmount,
    required String title,
    required DateTime date,
  });
}

/// Read-only view of the ledger context the SMS import flow needs: the
/// default currency and the account/category lists used to pick sensible
/// defaults when a candidate is imported without explicit overrides.
///
/// The lists are parallel (index-aligned) so they can be handed straight to
/// [SmsRuleMatcher] without the domain depending on the ledger's model types.
abstract interface class LedgerContext {
  /// The app's default currency code (e.g. `NPR`).
  String get defaultCurrency;

  /// Ids of all accounts, in display order.
  List<String> get accountIds;

  /// Types of all accounts, parallel to [accountIds].
  List<String> get accountTypes;

  /// Ids of all categories (including system ones), in display order.
  List<String> get categoryIds;

  /// Types of all categories, parallel to [categoryIds].
  List<String> get categoryTypes;

  /// Whether each category is a system category, parallel to [categoryIds].
  List<bool> get categoryIsSystem;
}

/// Durable SMS event-outbox repository.
///
/// Enqueue operations use an idempotency key so repeated receive/scan/retry
/// deliveries cannot create duplicate domain events.
abstract interface class SmsOutboxRepository {
  Future<bool> enqueueIfAbsent(SmsOutboxEvent event);

  Future<SmsOutboxEvent?> claimNext(DateTime now);

  Future<void> markCompleted(String eventId, DateTime processedAt);

  Future<void> requeue(
    String eventId, {
    required int attemptCount,
    required DateTime availableAt,
    required String? lastError,
  });

  Future<void> markDeadLetter(
    String eventId, {
    required int attemptCount,
    required DateTime processedAt,
    required String? lastError,
  });

  Future<List<SmsOutboxEvent>> getAll({int limit = 100});

  Future<int> countByStatus(SmsOutboxStatus status);
}

abstract interface class SmsVerificationRepository {
  Future<void> insertVerification(SmsVerification verification);
  Future<SmsVerification?> getVerification(String id);
  Future<List<SmsVerification>> getVerifications({int limit = 100});
  Future<void> updateVerification(SmsVerification verification);

  Future<void> insertLearningProposal(SmsLearningProposal proposal);
  Future<SmsLearningProposal?> findLearningProposal(
      String senderId, String normalizedPattern);
  Future<void> updateLearningProposal(SmsLearningProposal proposal);
  Future<List<SmsLearningProposal>> getLearningProposals(
      {String? status, int limit = 100});
}

abstract interface class SmsNotificationGateway {
  Future<void> notifyImported({
    required String inboxId,
    required String description,
  });

  Future<void> notifyVerificationRequired({
    required String inboxId,
    required String reason,
  });

  Future<void> notifyImportFailed({
    required String inboxId,
    required String reason,
  });
}
