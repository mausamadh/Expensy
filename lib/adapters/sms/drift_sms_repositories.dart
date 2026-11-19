// Adapters: Drift-backed repositories for the SMS import context.
//
// These implement the domain ports (lib/domain/sms_import/ports/ports.dart)
// over the existing AppDatabase/DBHelper SMS methods. They are the only
// place in the SMS context that touches the database layer.
import '../../database/db_helper.dart';
import '../../domain/sms_import/ports/ports.dart';
import '../../domain/sms_import/sms_entities.dart';

class DriftSmsInboxRepository implements SmsInboxRepository {
  const DriftSmsInboxRepository();

  @override
  Future<List<SmsInboxItem>> getAll() => DBHelper.getSmsInbox();

  @override
  Future<List<SmsInboxItem>> getByStatus(String status) =>
      DBHelper.getSmsInbox(status: status);

  @override
  Future<SmsInboxItem?> getByHash(String rawHash) =>
      DBHelper.getSmsInboxByHash(rawHash);

  @override
  Future<void> insert(SmsInboxItem item) => DBHelper.insertSmsInbox(item);

  @override
  Future<void> update(SmsInboxItem item) => DBHelper.updateSmsInbox(item);

  @override
  Future<void> delete(String id) => DBHelper.deleteSmsInbox(id);
}

class DriftSmsRuleRepository implements SmsRuleRepository {
  const DriftSmsRuleRepository();

  @override
  Future<List<SmsRule>> getAll() => DBHelper.getSmsRules();

  @override
  Future<void> insert(SmsRule rule) => DBHelper.insertSmsRule(rule);

  @override
  Future<void> update(SmsRule rule) => DBHelper.updateSmsRule(rule);

  @override
  Future<void> delete(String id) => DBHelper.deleteSmsRule(id);
}

class DriftSmsSenderPrefRepository implements SmsSenderPrefRepository {
  const DriftSmsSenderPrefRepository();

  @override
  Future<List<SmsSenderPref>> getAll() => DBHelper.getSmsSenderPrefs();

  @override
  Future<void> insert(SmsSenderPref pref) => DBHelper.insertSmsSenderPref(pref);

  @override
  Future<void> update(SmsSenderPref pref) =>
      DBHelper.updateSmsSenderPref(pref);

  @override
  Future<void> delete(String id) => DBHelper.deleteSmsSenderPref(id);
}
