// test/sms_sender_prefs_test.dart
//
// Covers the "sender preferences" feature: instead of blocking a whole
// sender, the user can (a) deny parsing for a sender entirely, and (b)
// suppress specific message kinds (otp / promotional / personal) per sender
// while transactional messages still surface. Also covers the SmsKind
// classifier that drives per-kind suppression.
//
// Phase 1 (hexagonal migration): the provider SMS slice was removed; these
// tests now drive the feature through [SmsInboxViewModel] via the shared
// harness, with a fake SMS source standing in for the plugin channel.
import 'package:drift/native.dart';
import 'package:finwick/database/app_database.dart';
import 'package:finwick/domain/sms_import/sms_entities.dart';
import 'package:finwick/domain/sms_import/sms_parser.dart';
import 'package:finwick/providers/app_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_clock.dart';
import 'helpers/sms_vm_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SmsKindClassifier', () {
    test('classifies OTP as otp even when transaction cues are present', () {
      expect(
        SmsKindClassifier.classify(
            'Your OTP is 482913. Do not share this code. Transaction of Rs. 500.'),
        SmsKind.otp,
      );
    });

    test('classifies a real transaction as transactional', () {
      expect(
        SmsKindClassifier.classify(
            'Khalti payment of Rs. 500 successful. Ref: KH123456.'),
        SmsKind.transactional,
      );
    });

    test('classifies a promo as promotional', () {
      expect(
        SmsKindClassifier.classify(
            'Win a free phone! Click now to claim your offer. T&C apply.'),
        SmsKind.promotional,
      );
    });

    test('classifies a personal message as personal', () {
      expect(
        SmsKindClassifier.classify('Hey, are we still on for dinner tonight?'),
        SmsKind.personal,
      );
    });

    test('a transaction with a marketing footer stays transactional', () {
      expect(
        SmsKindClassifier.classify(
            'Rs. 1,200 credited to your account. Offer: 5% cashback on all purchases!'),
        SmsKind.transactional,
      );
    });
  });

  group('Sender preferences', () {
    late AppProvider provider;
    late AppDatabase db;
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

    test('setSmsSenderParseAllowed remembers the sender and is idempotent',
        () async {
      await harness.vm.setSmsSenderParseAllowed('PROMO_999', false);
      expect(harness.vm.isSmsSenderParseAllowed('PROMO_999'), isFalse);
      expect(harness.vm.smsSenderPrefs, hasLength(1));

      // Second call must not duplicate.
      await harness.vm.setSmsSenderParseAllowed('PROMO_999', false);
      expect(harness.vm.smsSenderPrefs, hasLength(1));

      // Persists to the DB.
      final fromDb = await db.getSmsSenderPrefs();
      expect(fromDb, hasLength(1));
      expect(fromDb.first.senderId, 'PROMO_999');
      expect(fromDb.first.parseAllowed, isFalse);
    });

    test('resetSmsSenderPrefs removes the sender', () async {
      await harness.vm.setSmsSenderParseAllowed('PROMO_999', false);
      await harness.vm.resetSmsSenderPrefs('PROMO_999');
      expect(harness.vm.isSmsSenderParseAllowed('PROMO_999'), isTrue);
      expect(harness.vm.smsSenderPrefs, isEmpty);
      expect(await db.getSmsSenderPrefs(), isEmpty);
    });

    test('denying parsing dismisses the sender\'s pending inbox candidates',
        () async {
      final a = SmsInboxItem(
          id: 'i1', senderId: 'PROMO_999', body: 'x', rawHash: 'h1');
      final b = SmsInboxItem(
          id: 'i2', senderId: 'PROMO_999', body: 'y', rawHash: 'h2');
      final c =
          SmsInboxItem(id: 'i3', senderId: 'Khalti', body: 'z', rawHash: 'h3');
      await db.insertSmsInbox(a);
      await db.insertSmsInbox(b);
      await db.insertSmsInbox(c);
      await harness.load();

      await harness.vm.setSmsSenderParseAllowed('PROMO_999', false);

      final byId = {for (final i in harness.vm.smsInbox) i.id: i};
      expect(byId['i1']!.status, 'dismissed');
      expect(byId['i2']!.status, 'dismissed');
      expect(byId['i3']!.status, 'pending'); // untouched

      final dbA = await db.getSmsInboxByHash('h1');
      expect(dbA!.status, 'dismissed');
    });

    test('suppressSmsKind adds the kind and is idempotent', () async {
      await harness.vm.suppressSmsKind('BANK', 'otp');
      expect(harness.vm.isSmsKindSuppressed('BANK', 'otp'), isTrue);
      expect(harness.vm.smsSenderPrefs, hasLength(1));

      await harness.vm.suppressSmsKind('BANK', 'otp');
      expect(harness.vm.smsSenderPrefs, hasLength(1));
      expect(harness.vm.smsSenderPrefs.first.suppressedKinds, {'otp'});

      // A second kind is added, not replaced.
      await harness.vm.suppressSmsKind('BANK', 'promotional');
      expect(harness.vm.smsSenderPrefs.first.suppressedKinds,
          {'otp', 'promotional'});
    });

    test('suppressSmsKind never suppresses transactional', () async {
      await harness.vm.suppressSmsKind('BANK', 'transactional');
      expect(harness.vm.isSmsKindSuppressed('BANK', 'transactional'), isFalse);
      expect(harness.vm.smsSenderPrefs, isEmpty);
    });

    test('unsuppressSmsKind removes the kind', () async {
      await harness.vm.suppressSmsKind('BANK', 'otp');
      await harness.vm.unsuppressSmsKind('BANK', 'otp');
      expect(harness.vm.isSmsKindSuppressed('BANK', 'otp'), isFalse);
      expect(harness.vm.smsSenderPrefs.first.suppressedKinds, isEmpty);
    });

    test('scanAndImport skips a sender with parsing denied', () async {
      harness.source.messages = [
        const SmsMessage(
            id: '1',
            sender: 'BANK',
            body: 'Khalti payment of Rs. 500 successful',
            timestamp: 0),
        const SmsMessage(
            id: '2',
            sender: 'OTHER',
            body: 'Khalti payment of Rs. 300 successful',
            timestamp: 0),
      ];
      await harness.vm.setSmsSenderParseAllowed('BANK', false);

      final inserted = await harness.vm.scanSmsInbox();

      // Only the OTHER message is inserted; the denied sender is skipped
      // entirely (even though it is a real transaction).
      expect(inserted, 1);
      expect(harness.vm.smsInbox, hasLength(1));
      expect(harness.vm.smsInbox.first.senderId, 'OTHER');
    });

    test(
        'scanAndImport skips kind-suppressed non-transactional messages but '
        'keeps transactions from the same sender', () async {
      harness.source.messages = [
        // OTP from BANK — suppressed.
        const SmsMessage(
            id: '1',
            sender: 'BANK',
            body: 'Your OTP is 482913. Do not share this code.',
            timestamp: 0),
        // Promo from BANK — suppressed.
        const SmsMessage(
            id: '2',
            sender: 'BANK',
            body: 'Win a free phone! Click now to claim your offer.',
            timestamp: 0),
        // Real transaction from BANK — must still surface.
        const SmsMessage(
            id: '3',
            sender: 'BANK',
            body: 'Khalti payment of Rs. 500 successful. Ref: KH123456.',
            timestamp: 0),
      ];
      await harness.vm.suppressSmsKind('BANK', 'otp');
      await harness.vm.suppressSmsKind('BANK', 'promotional');

      final inserted = await harness.vm.scanSmsInbox();

      expect(inserted, 1);
      expect(harness.vm.smsInbox, hasLength(1));
      expect(harness.vm.smsInbox.first.senderId, 'BANK');
      expect(harness.vm.smsInbox.first.body,
          'Khalti payment of Rs. 500 successful. Ref: KH123456.');
    });

    test('scanAndImport inserts everything when there are no prefs', () async {
      harness.source.messages = [
        const SmsMessage(
            id: '1',
            sender: 'BANK',
            body: 'Your OTP is 482913. Do not share this code.',
            timestamp: 0),
        const SmsMessage(
            id: '2',
            sender: 'Khalti',
            body: 'Khalti payment of Rs. 500 successful',
            timestamp: 0),
      ];
      // autoHideOtp: false isolates the "no sender prefs" behaviour from the
      // global OTP filter (covered in its own group below).
      await harness.vm.setSmsAutoHideOtp(false);
      final inserted = await harness.vm.scanSmsInbox();
      expect(inserted, 2);
    });
  });

  group('Global OTP auto-hide', () {
    late AppProvider provider;
    late AppDatabase db;
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

    test('scanAndImport hides OTPs by default without any sender prefs',
        () async {
      harness.source.messages = [
        const SmsMessage(
            id: '1',
            sender: 'BANK',
            body: 'Your OTP is 482913. Do not share this code.',
            timestamp: 0),
        const SmsMessage(
            id: '2',
            sender: 'Khalti',
            body: 'Khalti payment of Rs. 500 successful',
            timestamp: 0),
      ];
      // Default (autoHideOtp: true) — the OTP is dropped, the transaction
      // still surfaces.
      final inserted = await harness.vm.scanSmsInbox();
      expect(inserted, 1);
      expect(harness.vm.smsInbox, hasLength(1));
      expect(harness.vm.smsInbox.first.senderId, 'Khalti');
    });

    test('scanAndImport keeps OTPs when autoHideOtp is disabled', () async {
      harness.source.messages = [
        const SmsMessage(
            id: '1',
            sender: 'BANK',
            body: 'Your OTP is 482913. Do not share this code.',
            timestamp: 0),
      ];
      await harness.vm.setSmsAutoHideOtp(false);
      final inserted = await harness.vm.scanSmsInbox();
      expect(inserted, 1);
      expect(harness.vm.smsInbox, hasLength(1));
      expect(harness.vm.smsInbox.first.senderId, 'BANK');
    });

    test('setSmsAutoHideOtp persists and flips the flag', () async {
      expect(harness.vm.smsAutoHideOtp, isTrue); // default on
      await harness.vm.setSmsAutoHideOtp(false);
      expect(harness.vm.smsAutoHideOtp, isFalse);
      await harness.vm.setSmsAutoHideOtp(true);
      expect(harness.vm.smsAutoHideOtp, isTrue);
    });
  });

  group('v34 migration (blocked senders -> sender prefs)', () {
    /// Opens an [AppDatabase] over an in-memory executor whose raw state is
    /// prepared by [setup] before drift applies its schema/migrations.
    Future<AppDatabase> _openAtV33(DatabaseSetup setup) async {
      final executor = NativeDatabase.memory(setup: setup);
      final migrated = AppDatabase(executor);
      AppDatabase.setInstanceForTesting(migrated);
      return migrated;
    }

    Future<void> _expectMigrated(AppDatabase migrated) async {
      // The migration must have run through the final SMS schema version.
      final version =
          await migrated.customSelect('PRAGMA user_version;').getSingle();
      expect(
          version.read<int>('user_version'), AppDatabase.currentSchemaVersion);

      // The old table is gone.
      final oldTables = await migrated
          .customSelect("SELECT name FROM sqlite_master "
              "WHERE type = 'table' AND name = 'sms_blocked_senders'")
          .get();
      expect(oldTables, isEmpty);

      // The new table exists and the row was carried over with parsing denied.
      final prefs = await migrated.getSmsSenderPrefs();
      expect(prefs, hasLength(1));
      expect(prefs.first.senderId, 'BANK_999');
      expect(prefs.first.parseAllowed, isFalse);
      expect(prefs.first.suppressedKinds, isEmpty);
    }

    test(
        'migrates sms_blocked_senders rows into sms_sender_prefs and drops '
        'the old table', () async {
      final migrated = await _openAtV33((db) {
        db.execute('CREATE TABLE sms_blocked_senders (id TEXT NOT NULL, '
            'sender_id TEXT NOT NULL, created_at TEXT NOT NULL, '
            'PRIMARY KEY (id))');
        db.execute(
            "INSERT INTO sms_blocked_senders (id, sender_id, created_at) "
            "VALUES ('b1', 'BANK_999', '2024-01-01T00:00:00.000')");
        db.execute('PRAGMA user_version = 33;');
      });

      await _expectMigrated(migrated);
      await migrated.close();
      AppDatabase.setInstanceForTesting(null);
    });

    test('self-heals an interrupted v34 migration (both tables present at v33)',
        () async {
      // The exact broken device state: user_version=33 with BOTH
      // sms_blocked_senders and sms_sender_prefs present (the createTable
      // committed before the INSERT failed). The idempotent guards must
      // carry the row over and drop the old table without error.
      final migrated = await _openAtV33((db) {
        db.execute('CREATE TABLE sms_blocked_senders (id TEXT NOT NULL, '
            'sender_id TEXT NOT NULL, created_at TEXT NOT NULL, '
            'PRIMARY KEY (id))');
        db.execute(
            "INSERT INTO sms_blocked_senders (id, sender_id, created_at) "
            "VALUES ('b1', 'BANK_999', '2024-01-01T00:00:00.000')");
        // The partially-created prefs table from the interrupted run.
        db.execute("CREATE TABLE sms_sender_prefs (id TEXT NOT NULL, "
            "sender_id TEXT NOT NULL, parse_allowed INTEGER NOT NULL DEFAULT 1, "
            "suppressed_kinds TEXT NOT NULL DEFAULT '', "
            "created_at TEXT NOT NULL, PRIMARY KEY (id))");
        db.execute('PRAGMA user_version = 33;');
      });

      await _expectMigrated(migrated);
      await migrated.close();
      AppDatabase.setInstanceForTesting(null);
    });
  });

  group('Decline / restore round-trip', () {
    late AppProvider provider;
    late AppDatabase db;
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

    test('dismissSmsCandidate marks dismissed in memory and DB', () async {
      final a =
          SmsInboxItem(id: 'd1', senderId: 'BANK', body: 'x', rawHash: 'dh1');
      await db.insertSmsInbox(a);
      await harness.load();

      await harness.vm.dismissSmsCandidate('d1');

      expect(harness.vm.smsInbox.first.status, 'dismissed');
      expect((await db.getSmsInboxByHash('dh1'))!.status, 'dismissed');
    });

    test('restoreSmsCandidate reverts a dismissed item back to pending',
        () async {
      final a =
          SmsInboxItem(id: 'd2', senderId: 'BANK', body: 'x', rawHash: 'dh2');
      await db.insertSmsInbox(a);
      await harness.load();

      await harness.vm.dismissSmsCandidate('d2');
      await harness.vm.restoreSmsCandidate('d2');

      expect(harness.vm.smsInbox.first.status, 'pending');
      expect((await db.getSmsInboxByHash('dh2'))!.status, 'pending');
    });

    test('restoreSmsCandidate is a no-op for unknown ids', () async {
      final a =
          SmsInboxItem(id: 'd3', senderId: 'BANK', body: 'x', rawHash: 'dh3');
      await db.insertSmsInbox(a);
      await harness.load();

      await harness.vm.restoreSmsCandidate('does-not-exist');

      expect(harness.vm.smsInbox, hasLength(1));
      expect(harness.vm.smsInbox.first.status, 'pending');
    });
  });
}
