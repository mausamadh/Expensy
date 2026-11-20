import 'package:finwick/application/mutation_gate.dart';
import 'package:finwick/domain/shared/clock.dart';
import 'package:finwick/domain/shared/uuid.dart';
import 'package:finwick/domain/sms_import/ports/ports.dart';
import 'package:finwick/domain/sms_import/sms_events.dart';

typedef SmsOutboxHandler = Future<void> Function(SmsOutboxEvent event);

class SmsOutboxPublishResult {
  final bool published;
  final SmsOutboxEvent event;

  const SmsOutboxPublishResult({
    required this.published,
    required this.event,
  });
}

class PublishSmsOutboxEvent {
  PublishSmsOutboxEvent({
    required this.repository,
    required this.gate,
    required this.clock,
    Uuid? uuid,
  }) : _uuid = uuid ?? Uuid();

  final SmsOutboxRepository repository;
  final MutationGate gate;
  final Clock clock;
  final Uuid _uuid;

  Future<SmsOutboxPublishResult> call({
    required String eventType,
    required String aggregateId,
    required String idempotencyKey,
    required Map<String, dynamic> payload,
  }) {
    return gate.run(() async {
      final now = clock.now();
      final event = SmsOutboxEvent(
        id: _uuid.v4(),
        eventType: eventType,
        aggregateId: aggregateId,
        idempotencyKey: idempotencyKey,
        payload: payload,
        availableAt: now,
        createdAt: now,
      );
      final published = await repository.enqueueIfAbsent(event);
      return SmsOutboxPublishResult(published: published, event: event);
    });
  }
}

class SmsOutboxDispatchResult {
  final bool dispatched;
  final SmsOutboxEvent? event;
  final String? error;

  const SmsOutboxDispatchResult({
    required this.dispatched,
    this.event,
    this.error,
  });
}

class DispatchNextSmsOutboxEvent {
  DispatchNextSmsOutboxEvent({
    required this.repository,
    required this.gate,
    required this.clock,
  });

  final SmsOutboxRepository repository;
  final MutationGate gate;
  final Clock clock;

  Future<SmsOutboxDispatchResult> call({
    required SmsOutboxHandler handler,
    int maxAttempts = 5,
  }) {
    return gate.run(() async {
      final now = clock.now();
      final event = await repository.claimNext(now);
      if (event == null) {
        return const SmsOutboxDispatchResult(dispatched: false);
      }

      try {
        await handler(event);
        final processedAt = clock.now();
        await repository.markCompleted(event.id, processedAt);
        return SmsOutboxDispatchResult(dispatched: true, event: event);
      } catch (error) {
        final attemptCount = event.attemptCount + 1;
        final errorText = error.toString();
        final processedAt = clock.now();
        if (attemptCount >= maxAttempts) {
          await repository.markDeadLetter(
            event.id,
            attemptCount: attemptCount,
            processedAt: processedAt,
            lastError: errorText,
          );
        } else {
          final retrySeconds = 1 << (attemptCount - 1);
          await repository.requeue(
            event.id,
            attemptCount: attemptCount,
            availableAt: processedAt.add(Duration(seconds: retrySeconds)),
            lastError: errorText,
          );
        }
        return SmsOutboxDispatchResult(
          dispatched: false,
          event: event,
          error: errorText,
        );
      }
    });
  }
}
