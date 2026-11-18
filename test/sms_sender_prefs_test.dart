// test/sms_sender_prefs_test.dart
//
// Covers the "sender preferences" feature: instead of blocking a whole
// sender, the user can (a) deny parsing for a sender entirely, and (b)
// suppress specific message kinds (otp / promotional / personal) per sender
// while transactional messages still surface. Also covers the SmsKind
// classifier that drives per-kind suppression.
import 'package:drift/native.dart';
import 'package:expensy/database/app_database.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/services/sms_import_service.dart';
import 'package:expensy/services/sms_parser/sms_parser.dart';
import 'package:expensy_sms/expensy_sms.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.ma.finwick/sms');

  /// Mocks the native channel so `scanSms` returns the given messages, the
  /// way the standard codec decodes a Kotlin `List<Map<String, Any?>>`.
  void mockScan(List<SmsMessage> messages) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'scanSms') {
        return messages
            .map((m) => <Object?, Object?>{
                  'id': m.id,
                  'sender': m.sender,
                  'body': m.body,
                  'timestamp': m.timestamp,
                })
            .toList();
      }
      return null;
    });
  }

  late AppDatabase db;
  late AppProvider provider;

  Map<String, SmsSenderPref> _prefMap() =>
      {for (final p in provider.smsSenderPrefs) p.senderId: p};

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
    test('setSmsSenderParseAllowed remembers the sender and is idempotent',
        () async {
      await provider.setSmsSenderParseAllowed('PROMO_999', false);
      expect(provider.isSmsSenderParseAllowed('PROMO_999'), isFalse);
      expect(provider.smsSenderPrefs, hasLength(1));

      // Second call must not duplicate.
      await provider.setSmsSenderParseAllowed('PROMO_999', false);
      expect(provider.smsSenderPrefs, hasLength(1));

      // Persists to the DB.
      final fromDb = await db.getSmsSenderPrefs();
      expect(fromDb, hasLength(1));
      expect(fromDb.first.senderId, 'PROMO_999');
      expect(fromDb.first.parseAllowed, isFalse);
    });

    test('resetSmsSenderPrefs removes the sender', () async {
      await provider.setSmsSenderParseAllowed('PROMO_999', false);
      await provider.resetSmsSenderPrefs('PROMO_999');
      expect(provider.isSmsSenderParseAllowed('PROMO_999'), isTrue);
      expect(provider.smsSenderPrefs, isEmpty);
      expect(await db.getSmsSenderPrefs(), isEmpty);
    });

    test('denying parsing dismisses the sender\'s pending inbox candidates',
        () async {
      final a = SmsInboxItem(
          id: 'i1', senderId: 'PROMO_999', body: 'x', rawHash: 'h1');
      final b = SmsInboxItem(
          id: 'i2', senderId: 'PROMO_999', body: 'y', rawHash: 'h2');
      final c = SmsInboxItem(
          id: 'i3', senderId: 'Khalti', body: 'z', rawHash: 'h3');
      await db.insertSmsInbox(a);
      await db.insertSmsInbox(b);
      await db.insertSmsInbox(c);
      provider.smsInbox = [a, b, c];

      await provider.setSmsSenderParseAllowed('PROMO_999', false);

      final byId = {for (final i in provider.smsInbox) i.id: i};
      expect(byId['i1']!.status, 'dismissed');
      expect(byId['i2']!.status, 'dismissed');
      expect(byId['i3']!.status, 'pending'); // untouched

      final dbA = await db.getSmsInboxByHash('h1');
      expect(dbA!.status, 'dismissed');
    });

    test('suppressSmsKind adds the kind and is idempotent', () async {
      await provider.suppressSmsKind('BANK', 'otp');
      expect(provider.isSmsKindSuppressed('BANK', 'otp'), isTrue);
      expect(provider.smsSenderPrefs, hasLength(1));

      await provider.suppressSmsKind('BANK', 'otp');
      expect(provider.smsSenderPrefs, hasLength(1));
      expect(provider.smsSenderPrefs.first.suppressedKinds, {'otp'});

      // A second kind is added, not replaced.
      await provider.suppressSmsKind('BANK', 'promotional');
      expect(provider.smsSenderPrefs.first.suppressedKinds,
          {'otp', 'promotional'});
    });

    test('suppressSmsKind never suppresses transactional', () async {
      await provider.suppressSmsKind('BANK', 'transactional');
      expect(provider.isSmsKindSuppressed('BANK', 'transactional'), isFalse);
      expect(provider.smsSenderPrefs, isEmpty);
    });

    test('unsuppressSmsKind removes the kind', () async {
      await provider.suppressSmsKind('BANK', 'otp');
      await provider.unsuppressSmsKind('BANK', 'otp');
      expect(provider.isSmsKindSuppressed('BANK', 'otp'), isFalse);
      expect(provider.smsSenderPrefs.first.suppressedKinds, isEmpty);
    });

    test('scanAndImport skips a sender with parsing denied', () async {
      mockScan(const [
        SmsMessage(
            id: 1,
            sender: 'BANK',
            body: 'Khalti payment of Rs. 500 successful',
            timestamp: 0),
        SmsMessage(
            id: 2,
            sender: 'OTHER',
            body: 'Khalti payment of Rs. 300 successful',
            timestamp: 0),
      ]);
      await provider.setSmsSenderParseAllowed('BANK', false);

      final service = SmsImportService(TemplateRegistry(const []));
      final inserted =
          await service.scanAndImport(senderPrefs: _prefMap());

      // Only the OTHER message is inserted; the denied sender is skipped
      // entirely (even though it is a real transaction).
      expect(inserted, hasLength(1));
      expect(inserted.first.senderId, 'OTHER');
    });

    test('scanAndImport skips kind-suppressed non-transactional messages but '
        'keeps transactions from the same sender', () async {
      mockScan(const [
        // OTP from BANK — suppressed.
        SmsMessage(
            id: 1,
            sender: 'BANK',
            body: 'Your OTP is 482913. Do not share this code.',
            timestamp: 0),
        // Promo from BANK — suppressed.
        SmsMessage(
            id: 2,
            sender: 'BANK',
            body: 'Win a free phone! Click now to claim your offer.',
            timestamp: 0),
        // Real transaction from BANK — must still surface.
        SmsMessage(
            id: 3,
            sender: 'BANK',
            body: 'Khalti payment of Rs. 500 successful. Ref: KH123456.',
            timestamp: 0),
      ]);
      await provider.suppressSmsKind('BANK', 'otp');
      await provider.suppressSmsKind('BANK', 'promotional');

      final service = SmsImportService(TemplateRegistry(const []));
      final inserted =
          await service.scanAndImport(senderPrefs: _prefMap());

      expect(inserted, hasLength(1));
      expect(inserted.first.senderId, 'BANK');
      expect(inserted.first.body,
          'Khalti payment of Rs. 500 successful. Ref: KH123456.');
    });

    test('scanAndImport inserts everything when there are no prefs', () async {
      mockScan(const [
        SmsMessage(
            id: 1,
            sender: 'BANK',
            body: 'Your OTP is 482913. Do not share this code.',
            timestamp: 0),
        SmsMessage(
            id: 2,
            sender: 'Khalti',
            body: 'Khalti payment of Rs. 500 successful',
            timestamp: 0),
      ]);
      final service = SmsImportService(TemplateRegistry(const []));
      // autoHideOtp: false isolates the "no sender prefs" behaviour from the
      // global OTP filter (covered in its own group below).
      final inserted = await service.scanAndImport(autoHideOtp: false);
      expect(inserted, hasLength(2));
    });
  });

  group('Global OTP auto-hide', () {
    test('scanAndImport hides OTPs by default without any sender prefs',
        () async {
      mockScan(const [
        SmsMessage(
            id: 1,
            sender: 'BANK',
            body: 'Your OTP is 482913. Do not share this code.',
            timestamp: 0),
        SmsMessage(
            id: 2,
            sender: 'Khalti',
            body: 'Khalti payment of Rs. 500 successful',
            timestamp: 0),
      ]);
      final service = SmsImportService(TemplateRegistry(const []));
      // Default (autoHideOtp: true) — the OTP is dropped, the transaction
      // still surfaces.
      final inserted = await service.scanAndImport();
      expect(inserted, hasLength(1));
      expect(inserted.first.senderId, 'Khalti');
    });

    test('scanAndImport keeps OTPs when autoHideOtp is disabled', () async {
      mockScan(const [
        SmsMessage(
            id: 1,
            sender: 'BANK',
            body: 'Your OTP is 482913. Do not share this code.',
            timestamp: 0),
      ]);
      final service = SmsImportService(TemplateRegistry(const []));
      final inserted = await service.scanAndImport(autoHideOtp: false);
      expect(inserted, hasLength(1));
      expect(inserted.first.senderId, 'BANK');
    });

    test('setSmsAutoHideOtp persists and flips the flag', () async {
      expect(provider.smsAutoHideOtp, isTrue); // default on
      await provider.setSmsAutoHideOtp(false);
      expect(provider.smsAutoHideOtp, isFalse);
      await provider.setSmsAutoHideOtp(true);
      expect(provider.smsAutoHideOtp, isTrue);
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
      // The migration must have run to completion: version bumped to 34.
      final version =
          await migrated.customSelect('PRAGMA user_version;').getSingle();
      expect(version.read<int>('user_version'), 34);

      // The old table is gone.
      final oldTables = await migrated
          .customSelect(
              "SELECT name FROM sqlite_master "
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

    test('migrates sms_blocked_senders rows into sms_sender_prefs and drops '
        'the old table', () async {
      final migrated = await _openAtV33((db) {
        db.execute(
            'CREATE TABLE sms_blocked_senders (id TEXT NOT NULL, '
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
        db.execute(
            'CREATE TABLE sms_blocked_senders (id TEXT NOT NULL, '
            'sender_id TEXT NOT NULL, created_at TEXT NOT NULL, '
            'PRIMARY KEY (id))');
        db.execute(
            "INSERT INTO sms_blocked_senders (id, sender_id, created_at) "
            "VALUES ('b1', 'BANK_999', '2024-01-01T00:00:00.000')");
        // The partially-created prefs table from the interrupted run.
        db.execute(
            "CREATE TABLE sms_sender_prefs (id TEXT NOT NULL, "
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
    test('dismissSmsCandidate marks dismissed in memory and DB', () async {
      final a = SmsInboxItem(
          id: 'd1', senderId: 'BANK', body: 'x', rawHash: 'dh1');
      await db.insertSmsInbox(a);
      provider.smsInbox = [a];

      await provider.dismissSmsCandidate('d1');

      expect(provider.smsInbox.first.status, 'dismissed');
      expect((await db.getSmsInboxByHash('dh1'))!.status, 'dismissed');
    });

    test('restoreSmsCandidate reverts a dismissed item back to pending',
        () async {
      final a = SmsInboxItem(
          id: 'd2', senderId: 'BANK', body: 'x', rawHash: 'dh2');
      await db.insertSmsInbox(a);
      provider.smsInbox = [a];

      await provider.dismissSmsCandidate('d2');
      await provider.restoreSmsCandidate('d2');

      expect(provider.smsInbox.first.status, 'pending');
      expect((await db.getSmsInboxByHash('dh2'))!.status, 'pending');
    });

    test('restoreSmsCandidate is a no-op for unknown ids', () async {
      final a = SmsInboxItem(
          id: 'd3', senderId: 'BANK', body: 'x', rawHash: 'dh3');
      await db.insertSmsInbox(a);
      provider.smsInbox = [a];

      await provider.restoreSmsCandidate('does-not-exist');

      expect(provider.smsInbox, hasLength(1));
      expect(provider.smsInbox.first.status, 'pending');
    });
  });
}
