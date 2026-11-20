import 'package:finwick/domain/sms_import/sms_entities.dart';
import 'package:finwick/domain/sms_import/sms_inbox_pipeline.dart';
import 'package:finwick/domain/sms_import/sms_parser.dart';
import 'package:finwick/application/mutation_gate.dart';
import 'package:finwick/application/sms_import/scan_sms_inbox.dart';
import 'package:finwick/domain/sms_import/ports/ports.dart';
import 'package:flutter_test/flutter_test.dart';

const _template = '''
{
  "id": "test_nabil_amount_tail",
  "senderId": "NABIL_ALERT",
  "serviceName": "Nabil amount with trailing metadata",
  "anchors": [{ "textBefore": "NPR ", "textAfter": " settled" }],
  "fields": [
    {
      "name": "AMOUNT",
      "anchor": { "textBefore": "NPR ", "textAfter": " settled" },
      "type": "CURRENCY"
    }
  ],
  "transactionDirection": "EXPENSE",
  "revision": 1,
  "isBuiltIn": true,
  "isActive": true
}
''';

const _body = 'NPR 315.25 withdrawn on 11/10/2026; Ref 1284 settled';

class _MemorySmsRepository implements SmsInboxRepository {
  _MemorySmsRepository(this.items);

  final List<SmsInboxItem> items;

  @override
  Future<List<SmsInboxItem>> getAll() async => List.of(items);

  @override
  Future<List<SmsInboxItem>> getByStatus(String status) async =>
      items.where((item) => item.status == status).toList();

  @override
  Future<SmsInboxItem?> getByHash(String rawHash) async {
    for (final item in items) {
      if (item.rawHash == rawHash) return item;
    }
    return null;
  }

  @override
  Future<void> insert(SmsInboxItem item) async => items.add(item);

  @override
  Future<void> update(SmsInboxItem item) async {
    final index = items.indexWhere((candidate) => candidate.id == item.id);
    if (index >= 0) items[index] = item;
  }

  @override
  Future<void> delete(String id) async =>
      items.removeWhere((item) => item.id == id);
}

class _FakeSmsSource implements SmsSource {
  _FakeSmsSource(this.messages);

  final List<SmsMessage> messages;

  @override
  Future<List<SmsMessage>> scanSms({int limit = 500}) async =>
      messages.take(limit).toList();

  @override
  Future<List<SmsSender>> getSenders() async => const [];

  @override
  Future<SmsPermissions> checkPermissions() async => const SmsPermissions(
        read: true,
        receive: true,
        isDefaultSmsApp: false,
      );

  @override
  Future<SmsPermissions> requestPermissions() => checkPermissions();

  @override
  Stream<SmsMessage> startLiveCapture() => const Stream.empty();

  @override
  Future<void> stopLiveCapture() async {}
}

void main() {
  final registry = TemplateRegistry.fromTemplateJson([_template]);

  test('refreshes existing pending candidates with the corrected parse',
      () async {
    const sender = 'NABIL_ALERT';
    final hash = await rawHashFor(sender, _body);
    final existing = SmsInboxItem(
      id: 'existing-pending',
      senderId: sender,
      body: _body,
      rawHash: hash,
      parsedType: null,
      parsedAmountMinorUnits: null,
      confidence: 'failed',
      status: 'pending',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    final result = await SmsInboxPipeline(registry).processBatch(
      const [
        SmsMessage(
          id: 'device-message',
          sender: sender,
          body: _body,
          timestamp: 1791720000000,
        ),
      ],
      const <String, SmsSenderPref>{},
      {hash},
      existingItems: {hash: existing},
    );

    expect(result.toInsert, isEmpty);
    expect(result.toUpdate, hasLength(1));
    expect(result.toUpdate.single.id, existing.id);
    expect(result.toUpdate.single.status, 'pending');
    expect(result.toUpdate.single.parsedAmountMinorUnits, 31525);
    expect(result.toUpdate.single.confidence, 'high');
    expect(result.toUpdate.single.createdAt, existing.createdAt);
  });

  test('does not reparse imported candidates', () async {
    const sender = 'NABIL_ALERT';
    final hash = await rawHashFor(sender, _body);
    final existing = SmsInboxItem(
      id: 'existing-imported',
      senderId: sender,
      body: _body,
      rawHash: hash,
      parsedType: 'expense',
      parsedAmountMinorUnits: 128400,
      status: 'imported',
      importedTxId: 'ledger-transaction',
    );
    final result = await SmsInboxPipeline(registry).processBatch(
      const [
        SmsMessage(
          id: 'device-message',
          sender: sender,
          body: _body,
          timestamp: 1791720000000,
        ),
      ],
      const <String, SmsSenderPref>{},
      {hash},
      existingItems: {hash: existing},
    );

    expect(result.toInsert, isEmpty);
    expect(result.toUpdate, isEmpty);
  });

  test('scan persists refreshed pending items but leaves imported items alone',
      () async {
    const sender = 'NABIL_ALERT';
    const importedBody = 'NPR 99.00 withdrawn on 11/10/2026; Ref 9999 settled';
    final pendingHash = await rawHashFor(sender, _body);
    final importedHash = await rawHashFor(sender, importedBody);
    final repository = _MemorySmsRepository([
      SmsInboxItem(
        id: 'existing-pending',
        senderId: sender,
        body: _body,
        rawHash: pendingHash,
        parsedAmountMinorUnits: null,
        confidence: 'failed',
        status: 'pending',
      ),
      SmsInboxItem(
        id: 'existing-imported',
        senderId: sender,
        body: importedBody,
        rawHash: importedHash,
        parsedAmountMinorUnits: 777,
        status: 'imported',
        importedTxId: 'ledger-transaction',
      ),
    ]);
    final scan = ScanSmsInbox(
      source: _FakeSmsSource([
        const SmsMessage(
          id: 'pending-message',
          sender: sender,
          body: _body,
          timestamp: 1791720000000,
        ),
        const SmsMessage(
          id: 'imported-message',
          sender: sender,
          body: importedBody,
          timestamp: 1791720000000,
        ),
      ]),
      inboxRepo: repository,
      registry: registry,
      gate: MutationGate(),
    );

    final outcome = await scan(
      senderPrefs: const {},
      autoHideOtp: true,
      defaultCurrency: 'NPR',
    );

    expect(outcome.insertedCount, 0);
    expect(outcome.refreshedItemIds, ['existing-pending']);
    expect(
      (await repository.getByHash(pendingHash))!.parsedAmountMinorUnits,
      31525,
    );
    expect(
      (await repository.getByHash(importedHash))!.parsedAmountMinorUnits,
      777,
    );
  });
}
