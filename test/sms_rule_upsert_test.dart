// test/sms_rule_upsert_test.dart
// Verifies that the sender→account/category mapping is always remembered on
// import (upserted, never duplicated) and that saveSmsRule upserts by
// sender + merchant pattern.

import 'package:drift/native.dart';
import 'package:finwick/database/app_database.dart';
import 'package:finwick/models/models.dart';
import 'package:finwick/providers/app_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_clock.dart';
import 'helpers/sms_vm_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AppProvider provider;
  late SmsVmHarness harness;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    AppDatabase.setInstanceForTesting(db);
    provider = AppProvider();
    await provider.load();
    harness = SmsVmHarness(provider, FakeSmsSource(), FakeClock());
    await harness.load();
  });

  tearDown(() async {
    await db.close();
    AppDatabase.setInstanceForTesting(null);
  });

  Account _acc(String id, String name) =>
      Account(id: id, name: name, type: 'bank', balance: 1000, colorValue: 0xFF1565C0);

  AppCategory _cat(String id, String name, String type) =>
      AppCategory(id: id, name: name, type: type, colorValue: 0xFF607D8B);

  SmsInboxItem _item(String id, {String sender = 'BANK', String? merchant}) =>
      SmsInboxItem(
        id: id,
        senderId: sender,
        body: 'You paid 100.00 to $merchant',
        rawHash: 'hash-$id',
        parsedMerchant: merchant,
      );

  group('importSmsCandidate — always remembers the mapping', () {
    test('creates a rule on first import (expense)', () async {
      final a = _acc('acc-a', 'A');
      final cat = _cat('cat-food', 'Food', 'expense');
      await provider.addAccount(a);
      await provider.addCategory(cat);

      final item = _item('sms-1', merchant: 'CAFE');
      await db.insertSmsInbox(item);
      await harness.load();

      final txId = await harness.vm.importSmsCandidate(
        item.id,
        type: 'expense',
        amount: 100.0,
        accountId: a.id,
        categoryId: cat.id,
      );

      expect(txId, isNotNull);
      expect(harness.vm.smsRules, hasLength(1));
      final rule = harness.vm.smsRules.single;
      expect(rule.senderId, 'BANK');
      expect(rule.accountId, a.id);
      expect(rule.categoryId, cat.id);
      expect(rule.transactionType, 'expense');
      expect(rule.merchantPattern, 'CAFE');
    });

    test('upserts the existing rule on a second import (no duplicate)',
        () async {
      final a = _acc('acc-a', 'A');
      final b = _acc('acc-b', 'B');
      final cat = _cat('cat-food', 'Food', 'expense');
      await provider.addAccount(a);
      await provider.addAccount(b);
      await provider.addCategory(cat);

      // First import maps BANK → A.
      final item1 = _item('sms-1', merchant: 'CAFE');
      await db.insertSmsInbox(item1);
      await harness.load();
      await harness.vm.importSmsCandidate(
        item1.id,
        type: 'expense',
        amount: 100.0,
        accountId: a.id,
        categoryId: cat.id,
      );
      expect(harness.vm.smsRules, hasLength(1));

      // Second import from the same sender maps to B — the rule must be
      // updated in place, not duplicated.
      final item2 = _item('sms-2', merchant: 'CAFE');
      await db.insertSmsInbox(item2);
      await harness.load();
      await harness.vm.importSmsCandidate(
        item2.id,
        type: 'expense',
        amount: 50.0,
        accountId: b.id,
        categoryId: cat.id,
      );

      expect(harness.vm.smsRules, hasLength(1));
      final rule = harness.vm.smsRules.single;
      expect(rule.accountId, b.id, reason: 'rule should be updated to the latest account');
      expect(rule.senderId, 'BANK');
    });

    test('smsRuleForItem returns the matched rule for pre-fill', () async {
      final a = _acc('acc-a', 'A');
      final cat = _cat('cat-food', 'Food', 'expense');
      await provider.addAccount(a);
      await provider.addCategory(cat);

      final item1 = _item('sms-1', merchant: 'CAFE');
      await db.insertSmsInbox(item1);
      await harness.load();
      await harness.vm.importSmsCandidate(
        item1.id,
        type: 'expense',
        amount: 100.0,
        accountId: a.id,
        categoryId: cat.id,
      );

      // A fresh item from the same sender should match the saved rule.
      final item2 = _item('sms-2', merchant: 'CAFE');
      final rule = harness.vm.smsRuleForItem(item2);
      expect(rule, isNotNull);
      expect(rule!.accountId, a.id);
      expect(rule.categoryId, cat.id);
      expect(rule.transactionType, 'expense');
    });
  });

  group('saveSmsRule — upserts by sender + merchant pattern', () {
    test('updates an existing rule instead of duplicating', () async {
      final a = _acc('acc-a', 'A');
      final b = _acc('acc-b', 'B');
      final cat = _cat('cat-food', 'Food', 'expense');
      await provider.addAccount(a);
      await provider.addAccount(b);
      await provider.addCategory(cat);

      await harness.vm.saveSmsRule(
        senderId: 'BANK',
        merchantPattern: 'CAFE',
        accountId: a.id,
        categoryId: cat.id,
        transactionType: 'expense',
      );
      expect(harness.vm.smsRules, hasLength(1));

      // Same sender + pattern, different account → update in place.
      await harness.vm.saveSmsRule(
        senderId: 'BANK',
        merchantPattern: 'CAFE',
        accountId: b.id,
        categoryId: cat.id,
        transactionType: 'expense',
      );
      expect(harness.vm.smsRules, hasLength(1));
      expect(harness.vm.smsRules.single.accountId, b.id);
    });

    test('keeps distinct merchant patterns as separate rules', () async {
      final a = _acc('acc-a', 'A');
      final b = _acc('acc-b', 'B');
      final cat = _cat('cat-food', 'Food', 'expense');
      await provider.addAccount(a);
      await provider.addAccount(b);
      await provider.addCategory(cat);

      await harness.vm.saveSmsRule(
        senderId: 'BANK',
        merchantPattern: 'CAFE',
        accountId: a.id,
        categoryId: cat.id,
        transactionType: 'expense',
      );
      await harness.vm.saveSmsRule(
        senderId: 'BANK',
        merchantPattern: 'MARKET',
        accountId: b.id,
        categoryId: cat.id,
        transactionType: 'expense',
      );

      expect(harness.vm.smsRules, hasLength(2));
    });
  });
}
