// Adapters: Drift-backed repositories for the SMS import context.
//
// These implement the domain ports (lib/domain/sms_import/ports/ports.dart)
// over the existing AppDatabase SMS methods. They are the only
// place in the SMS context that touches the database layer.
import '../../database/app_database.dart';
import '../../domain/sms_import/ports/ports.dart';
import '../../domain/sms_import/sms_entities.dart';

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
  Future<void> insert(SmsInboxItem item) => AppDatabase.instance.insertSmsInbox(item);

  @override
  Future<void> update(SmsInboxItem item) => AppDatabase.instance.updateSmsInbox(item);

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
  Future<List<SmsSenderPref>> getAll() => AppDatabase.instance.getSmsSenderPrefs();

  @override
  Future<void> insert(SmsSenderPref pref) => AppDatabase.instance.insertSmsSenderPref(pref);

  @override
  Future<void> update(SmsSenderPref pref) =>
      AppDatabase.instance.updateSmsSenderPref(pref);

  @override
  Future<void> delete(String id) => AppDatabase.instance.deleteSmsSenderPref(id);
}
