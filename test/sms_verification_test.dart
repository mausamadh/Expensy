import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:finwick/adapters/sms/drift_sms_repositories.dart';
import 'package:finwick/application/mutation_gate.dart';
import 'package:finwick/application/sms_import/verification_use_cases.dart';
import 'package:finwick/database/app_database.dart';
import 'package:finwick/domain/sms_import/sms_entities.dart';
import 'package:finwick/domain/sms_import/sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_clock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeClock clock;
  late DriftSmsOutboxRepository outbox;
  late DriftSmsVerificationRepository verificationRepo;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    AppDatabase.setInstanceForTesting(db);
    clock = FakeClock(DateTime.utc(2026, 11, 20, 9));
    outbox = const DriftSmsOutboxRepository();
    verificationRepo = const DriftSmsVerificationRepository();
  });

  tearDown(() async {
    AppDatabase.setInstanceForTesting(null);
    await db.close();
  });

  test('unsafe transfer verification is rejected', () async {
    final submit = SubmitSmsVerification(
      verificationRepo: verificationRepo,
      outboxRepo: outbox,
      gate: MutationGate(),
      clock: clock,
    );

    final result = await submit(
      inboxId: 'inbox-1',
      senderId: 'BANK',
      rawHash: 'hash-1',
      body: 'Rs. 100 transferred',
      corrections: {
        'type': 'transfer',
        'accountId': 'account-1',
        'toAccountId': 'account-1',
        'categoryId': 'sys_transfer',
      },
    );

    expect(result, isNull);
  });

  test('confirmed corrections create a draft then activate after threshold',
      () async {
    final submit = SubmitSmsVerification(
      verificationRepo: verificationRepo,
      outboxRepo: outbox,
      gate: MutationGate(),
      clock: clock,
    );
    final apply = ApplySmsVerification(
      verificationRepo: verificationRepo,
      outboxRepo: outbox,
      gate: MutationGate(),
      clock: clock,
    );

    for (var i = 0; i < 3; i++) {
      final submitted = await submit(
        inboxId: 'inbox-$i',
        senderId: 'BANK',
        rawHash: 'hash-$i',
        body: 'Rs. $i paid to grocery shop',
        corrections: {
          'type': 'expense',
          'amount': i + 100,
          'currency': 'NPR',
          'accountId': 'account-1',
          'categoryId': 'category-food',
        },
      );
      expect(submitted, isNotNull);
      await apply(verificationId: submitted!.id, activationThreshold: 3);
    }

    final proposals =
        await verificationRepo.getLearningProposals(status: 'active');
    expect(proposals, hasLength(1));
    expect(proposals.first.confirmationCount, 3);
  });

  test('transfer learning activation preserves transfer safety', () async {
    final submit = SubmitSmsVerification(
      verificationRepo: verificationRepo,
      outboxRepo: outbox,
      gate: MutationGate(),
      clock: clock,
    );
    final apply = ApplySmsVerification(
      verificationRepo: verificationRepo,
      outboxRepo: outbox,
      gate: MutationGate(),
      clock: clock,
    );
    final submitted = await submit(
      inboxId: 'inbox-transfer',
      senderId: 'BANK',
      rawHash: 'hash-transfer',
      body: 'Rs. 500 transferred to savings',
      corrections: {
        'type': 'transfer',
        'accountId': 'account-1',
        'toAccountId': 'account-2',
        'categoryId': 'sys_transfer',
      },
    );
    expect(submitted, isNotNull);
    final proposal =
        await apply(verificationId: submitted!.id, activationThreshold: 1);

    expect(proposal, isNotNull);
    expect(proposal!.status, 'active');
  });

  test('active learning proposal overrides failed parse fields', () async {
    final body = 'Bank debit 125 on 20/11/2026';
    final proposal = SmsLearningProposal(
      id: 'proposal-1',
      senderId: 'BANK',
      normalizedPattern: normalizeSmsLearningPattern(body),
      corrections: {
        'type': 'expense',
        'amount': 125,
        'currency': 'NPR',
        'merchant': 'Grocery',
        'reference': 'REF-1',
      },
      status: 'active',
      confirmationCount: 3,
      createdAt: clock.now(),
    );

    final item = SmsInboxItem(
      id: 'inbox-learned',
      senderId: 'BANK',
      body: body,
      rawHash: 'hash-learned',
      confidence: 'failed',
    );
    const matcher = SmsLearningMatcher();
    final match = matcher.match('BANK', body, [proposal]);

    expect(match, isNotNull);
    final learned = matcher.apply(item, match!);
    expect(learned.parsedType, 'expense');
    expect(learned.parsedAmountMinorUnits, 12500);
    expect(learned.parsedCurrency, 'NPR');
    expect(learned.parsedMerchant, 'Grocery');
    expect(learned.confidence, 'high');
  });

  test('import policy requires verification for ambiguous candidates', () {
    const policy = SmsImportPolicy();
    final decision = policy.decide(
      mode: SmsImportMode.conservative,
      parsedType: 'expense',
      amountMinorUnits: 1000,
      currency: 'NPR',
      confidence: 'medium',
      accountId: 'account-1',
      categoryId: 'category-food',
      toAccountId: null,
    );

    expect(decision.shouldAutoImport, isFalse);
    expect(decision.reason, contains('confidence'));
  });

  test('import policy auto-imports high-confidence transfer safely', () {
    const policy = SmsImportPolicy();
    final decision = policy.decide(
      mode: SmsImportMode.balanced,
      parsedType: 'transfer',
      amountMinorUnits: 50000,
      currency: 'NPR',
      confidence: 'high',
      accountId: 'account-1',
      categoryId: 'sys_transfer',
      toAccountId: 'account-2',
    );

    expect(decision.shouldAutoImport, isTrue);
  });
}
