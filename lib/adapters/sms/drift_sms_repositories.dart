// Adapters: Drift-backed repositories for the SMS import context.
//
// These implement the domain ports (lib/domain/sms_import/ports/ports.dart)
// over the existing AppDatabase SMS methods. They are the only
// place in the SMS context that touches the database layer.
import '../../database/app_database.dart';
import '../../domain/sms_import/ports/ports.dart';
import '../../domain/sms_import/sms_entities.dart';
import '../../domain/sms_import/sms_events.dart';
import '../../domain/sms_import/sms_verification.dart';

class DriftSmsInboxRepository implements SmsInboxRepository {
  const DriftSmsInboxRepository();

  @override
  Future<List<SmsInboxItem>> getAll() => AppDatabase.instance.getSmsInbox();

  @override
  Future<List<SmsInboxItem>> getByStatus(String status) =>
      AppDatabase.instance.getSmsInbox(status: status);

  @override
  Future<SmsInboxItem?> getByHash(String rawHash) =>
      AppDatabase.instance.getSmsInboxByHash(rawHash);

  @override
  Future<void> insert(SmsInboxItem item) =>
      AppDatabase.instance.insertSmsInbox(item);

  @override
  Future<void> update(SmsInboxItem item) =>
      AppDatabase.instance.updateSmsInbox(item);

  @override
  Future<void> delete(String id) => AppDatabase.instance.deleteSmsInbox(id);
}

class DriftSmsRuleRepository implements SmsRuleRepository {
  const DriftSmsRuleRepository();

  @override
  Future<List<SmsRule>> getAll() => AppDatabase.instance.getSmsRules();

  @override
  Future<void> insert(SmsRule rule) => AppDatabase.instance.insertSmsRule(rule);

  @override
  Future<void> update(SmsRule rule) => AppDatabase.instance.updateSmsRule(rule);

  @override
  Future<void> delete(String id) => AppDatabase.instance.deleteSmsRule(id);
}

class DriftSmsSenderPrefRepository implements SmsSenderPrefRepository {
  const DriftSmsSenderPrefRepository();

  @override
  Future<List<SmsSenderPref>> getAll() =>
      AppDatabase.instance.getSmsSenderPrefs();

  @override
  Future<void> insert(SmsSenderPref pref) =>
      AppDatabase.instance.insertSmsSenderPref(pref);

  @override
  Future<void> update(SmsSenderPref pref) =>
      AppDatabase.instance.updateSmsSenderPref(pref);

  @override
  Future<void> delete(String id) =>
      AppDatabase.instance.deleteSmsSenderPref(id);
}

class DriftSmsOutboxRepository implements SmsOutboxRepository {
  const DriftSmsOutboxRepository();

  @override
  Future<bool> enqueueIfAbsent(SmsOutboxEvent event) =>
      AppDatabase.instance.enqueueSmsOutboxEvent(event);

  @override
  Future<SmsOutboxEvent?> claimNext(DateTime now) =>
      AppDatabase.instance.claimNextSmsOutboxEvent(now);

  @override
  Future<void> markCompleted(String eventId, DateTime processedAt) =>
      AppDatabase.instance.completeSmsOutboxEvent(eventId, processedAt);

  @override
  Future<void> requeue(
    String eventId, {
    required int attemptCount,
    required DateTime availableAt,
    required String? lastError,
  }) =>
      AppDatabase.instance.requeueSmsOutboxEvent(
        eventId,
        attemptCount: attemptCount,
        availableAt: availableAt,
        lastError: lastError,
      );

  @override
  Future<void> markDeadLetter(
    String eventId, {
    required int attemptCount,
    required DateTime processedAt,
    required String? lastError,
  }) =>
      AppDatabase.instance.deadLetterSmsOutboxEvent(
        eventId,
        attemptCount: attemptCount,
        processedAt: processedAt,
        lastError: lastError,
      );

  @override
  Future<List<SmsOutboxEvent>> getAll({int limit = 100}) =>
      AppDatabase.instance.getSmsOutboxEvents(limit: limit);

  @override
  Future<int> countByStatus(SmsOutboxStatus status) =>
      AppDatabase.instance.countSmsOutboxByStatus(status);
}

class DriftSmsVerificationRepository implements SmsVerificationRepository {
  const DriftSmsVerificationRepository();

  @override
  Future<void> insertVerification(SmsVerification verification) =>
      AppDatabase.instance.insertSmsVerification(verification);

  @override
  Future<SmsVerification?> getVerification(String id) =>
      AppDatabase.instance.getSmsVerification(id);

  @override
  Future<List<SmsVerification>> getVerifications({int limit = 100}) =>
      AppDatabase.instance.getSmsVerifications(limit: limit);

  @override
  Future<void> updateVerification(SmsVerification verification) =>
      AppDatabase.instance.updateSmsVerification(verification);

  @override
  Future<void> insertLearningProposal(SmsLearningProposal proposal) =>
      AppDatabase.instance.insertSmsLearningProposal(proposal);

  @override
  Future<SmsLearningProposal?> findLearningProposal(
          String senderId, String normalizedPattern) =>
      AppDatabase.instance.findSmsLearningProposal(senderId, normalizedPattern);

  @override
  Future<void> updateLearningProposal(SmsLearningProposal proposal) =>
      AppDatabase.instance.updateSmsLearningProposal(proposal);

  @override
  Future<List<SmsLearningProposal>> getLearningProposals(
          {String? status, int limit = 100}) =>
      AppDatabase.instance
          .getSmsLearningProposals(status: status, limit: limit);
}
