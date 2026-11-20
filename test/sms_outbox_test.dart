import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:finwick/adapters/sms/drift_sms_repositories.dart';
import 'package:finwick/application/mutation_gate.dart';
import 'package:finwick/application/sms_import/sms_outbox_use_cases.dart';
import 'package:finwick/database/app_database.dart';
import 'package:finwick/domain/sms_import/sms_events.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_clock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeClock clock;
  late DriftSmsOutboxRepository repository;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    AppDatabase.setInstanceForTesting(db);
    clock = FakeClock(DateTime.utc(2026, 11, 20, 9));
    repository = const DriftSmsOutboxRepository();
  });

  tearDown(() async {
    AppDatabase.setInstanceForTesting(null);
    await db.close();
  });

  test('publishes an SMS event once by idempotency key', () async {
    final publish = PublishSmsOutboxEvent(
      repository: repository,
      gate: MutationGate(),
      clock: clock,
    );

    final first = await publish(
      eventType: SmsDomainEventNames.received,
      aggregateId: 'sms-1',
      idempotencyKey: 'sender:raw-body',
      payload: {'sender': 'BANK', 'body': 'Paid Rs. 100'},
    );
    final duplicate = await publish(
      eventType: SmsDomainEventNames.received,
      aggregateId: 'sms-1',
      idempotencyKey: 'sender:raw-body',
      payload: {'sender': 'BANK', 'body': 'Paid Rs. 100'},
    );

    expect(first.published, isTrue);
    expect(duplicate.published, isFalse);
    expect(await repository.countByStatus(SmsOutboxStatus.queued), 1);
  });

  test('dispatches and completes a queued SMS event', () async {
    final publish = PublishSmsOutboxEvent(
      repository: repository,
      gate: MutationGate(),
      clock: clock,
    );
    await publish(
      eventType: SmsDomainEventNames.parseRequested,
      aggregateId: 'sms-2',
      idempotencyKey: 'sms-2',
      payload: {'body': 'Rs. 250 debited'},
    );

    final dispatch = DispatchNextSmsOutboxEvent(
      repository: repository,
      gate: MutationGate(),
      clock: clock,
    );
    SmsOutboxEvent? handled;
    final result = await dispatch(
      handler: (event) async => handled = event,
    );

    expect(result.dispatched, isTrue);
    expect(handled?.eventType, SmsDomainEventNames.parseRequested);
    expect(await repository.countByStatus(SmsOutboxStatus.completed), 1);
  });

  test('failed SMS event is requeued for retry', () async {
    final publish = PublishSmsOutboxEvent(
      repository: repository,
      gate: MutationGate(),
      clock: clock,
    );
    await publish(
      eventType: SmsDomainEventNames.importFailed,
      aggregateId: 'sms-3',
      idempotencyKey: 'sms-3',
      payload: {'reason': 'account missing'},
    );

    final dispatch = DispatchNextSmsOutboxEvent(
      repository: repository,
      gate: MutationGate(),
      clock: clock,
    );
    final result = await dispatch(
      handler: (_) async => throw StateError('temporary failure'),
      maxAttempts: 5,
    );

    expect(result.dispatched, isFalse);
    expect(result.error, contains('temporary failure'));
    expect(await repository.countByStatus(SmsOutboxStatus.queued), 1);
  });

  test('SMS event reaches dead letter after maximum attempts', () async {
    final publish = PublishSmsOutboxEvent(
      repository: repository,
      gate: MutationGate(),
      clock: clock,
    );
    await publish(
      eventType: SmsDomainEventNames.importRequested,
      aggregateId: 'sms-4',
      idempotencyKey: 'sms-4',
      payload: const {},
    );

    final dispatch = DispatchNextSmsOutboxEvent(
      repository: repository,
      gate: MutationGate(),
      clock: clock,
    );
    await dispatch(
      handler: (_) async => throw StateError('permanent failure'),
      maxAttempts: 1,
    );

    expect(await repository.countByStatus(SmsOutboxStatus.deadLetter), 1);
  });
}
