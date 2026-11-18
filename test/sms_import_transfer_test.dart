// test/sms_import_transfer_test.dart
// Verifies that importSmsCandidate honours a user-chosen transfer destination
// (toAccountId) instead of auto-picking the first other account.

import 'package:drift/native.dart';
import 'package:expensy/database/app_database.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AppProvider provider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    AppDatabase.setInstanceForTesting(db);
    provider = AppProvider();
    await provider.load();
  });

  tearDown(() async {
    await db.close();
    AppDatabase.setInstanceForTesting(null);
  });

  SmsInboxItem _item(String id) => SmsInboxItem(
        id: id,
        senderId: 'BANK',
        body: 'You transferred 500.00 to SAVINGS',
        rawHash: 'hash-$id',
      );

  group('importSmsCandidate — transfer destination', () {
    test('uses the user-chosen toAccountId, not the auto-picked account',
        () async {
      final a = Account(
          id: 'acc-a', name: 'A', type: 'bank', balance: 1000, colorValue: 0xFF1565C0);
      final b = Account(
          id: 'acc-b', name: 'B', type: 'bank', balance: 100, colorValue: 0xFF2E7D32);
      final c = Account(
          id: 'acc-c', name: 'C', type: 'cash', balance: 50, colorValue: 0xFF43A047);
      await provider.addAccount(a);
      await provider.addAccount(b);
      await provider.addAccount(c);

      final item = _item('sms-1');
      provider.smsInbox = [item];

      // Source = A. Auto-pick would choose B (first other account).
      // User explicitly chooses C as the destination.
      final txId = await provider.importSmsCandidate(
        item.id,
        type: 'transfer',
        amount: 500.0,
        accountId: a.id,
        toAccountId: c.id,
      );

      expect(txId, isNotNull);

      // Balances: A debited 500, C credited 500, B untouched.
      expect(provider.accountById(a.id)!.balance, closeTo(500.0, 0.01));
      expect(provider.accountById(c.id)!.balance, closeTo(550.0, 0.01));
      expect(provider.accountById(b.id)!.balance, closeTo(100.0, 0.01));

      // Both legs exist, share a transferGroupId, and use sys_transfer.
      final legs = provider.transactions
          .where((t) => t.transferGroupId != null)
          .toList();
      expect(legs.length, 2);
      final groupId = legs.first.transferGroupId!;
      expect(legs.every((t) => t.transferGroupId == groupId), isTrue);
      expect(legs.every((t) => t.categoryId == 'sys_transfer'), isTrue);

      // The credit leg lands on the user-chosen account C.
      final credit = legs.firstWhere((t) => t.type == 'income');
      expect(credit.accountId, c.id);
      final debit = legs.firstWhere((t) => t.type == 'expense');
      expect(debit.accountId, a.id);

      // Inbox item marked imported.
      expect(provider.smsInbox.first.status, 'imported');
    });

    test('rejects a transfer whose destination equals the source', () async {
      final a = Account(
          id: 'acc-a', name: 'A', type: 'bank', balance: 1000, colorValue: 0xFF1565C0);
      final b = Account(
          id: 'acc-b', name: 'B', type: 'bank', balance: 100, colorValue: 0xFF2E7D32);
      await provider.addAccount(a);
      await provider.addAccount(b);

      final item = _item('sms-2');
      provider.smsInbox = [item];

      // toAccountId == accountId -> must be rejected (no transaction created).
      final txId = await provider.importSmsCandidate(
        item.id,
        type: 'transfer',
        amount: 500.0,
        accountId: a.id,
        toAccountId: a.id,
      );

      expect(txId, isNull);
      expect(provider.transactions, isEmpty);
      expect(provider.accountById(a.id)!.balance, closeTo(1000.0, 0.01));
      expect(provider.smsInbox.first.status, 'pending');
    });

    test('falls back to auto-pick when toAccountId is omitted', () async {
      final a = Account(
          id: 'acc-a', name: 'A', type: 'bank', balance: 1000, colorValue: 0xFF1565C0);
      final b = Account(
          id: 'acc-b', name: 'B', type: 'bank', balance: 100, colorValue: 0xFF2E7D32);
      await provider.addAccount(a);
      await provider.addAccount(b);

      final item = _item('sms-3');
      provider.smsInbox = [item];

      // No toAccountId -> auto-picks B (the only other account).
      final txId = await provider.importSmsCandidate(
        item.id,
        type: 'transfer',
        amount: 200.0,
        accountId: a.id,
      );

      expect(txId, isNotNull);
      expect(provider.accountById(a.id)!.balance, closeTo(800.0, 0.01));
      expect(provider.accountById(b.id)!.balance, closeTo(300.0, 0.01));
    });
  });
}
