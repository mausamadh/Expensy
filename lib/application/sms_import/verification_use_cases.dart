import 'package:finwick/application/mutation_gate.dart';
import 'package:finwick/domain/shared/clock.dart';
import 'package:finwick/domain/shared/uuid.dart';
import 'package:finwick/domain/sms_import/ports/ports.dart';
import 'package:finwick/domain/sms_import/sms_events.dart';
import 'package:finwick/domain/sms_import/sms_verification.dart';

class SubmitSmsVerification {
  SubmitSmsVerification({
    required this.verificationRepo,
    required this.outboxRepo,
    required this.gate,
    required this.clock,
    Uuid? uuid,
  }) : _uuid = uuid ?? Uuid();

  final SmsVerificationRepository verificationRepo;
  final SmsOutboxRepository outboxRepo;
  final MutationGate gate;
  final Clock clock;
  final Uuid _uuid;

  Future<SmsVerification?> call({
    required String inboxId,
    required String senderId,
    required String rawHash,
    required String body,
    required Map<String, dynamic> corrections,
  }) {
    return gate.run(() async {
      final type = (corrections['type'] as String?)?.toLowerCase();
      if (type == 'transfer') {
        final source = corrections['accountId'] as String?;
        final destination = corrections['toAccountId'] as String?;
        final categoryId = corrections['categoryId'] as String?;
        if (source == null ||
            destination == null ||
            source.isEmpty ||
            destination.isEmpty ||
            source == destination ||
            categoryId != 'sys_transfer') {
          return null;
        }
      }

      final now = clock.now();
      final verification = SmsVerification(
        id: _uuid.v4(),
        inboxId: inboxId,
        senderId: senderId,
        rawHash: rawHash,
        body: body,
        corrections: Map<String, dynamic>.from(corrections),
        createdAt: now,
      );
      await verificationRepo.insertVerification(verification);
      await outboxRepo.enqueueIfAbsent(SmsOutboxEvent(
        id: _uuid.v4(),
        eventType: SmsDomainEventNames.verificationSubmitted,
        aggregateId: verification.id,
        idempotencyKey: 'sms-verification:${verification.id}',
        payload: {
          'verificationId': verification.id,
          'inboxId': inboxId,
          'senderId': senderId,
          'rawHash': rawHash,
        },
        availableAt: now,
        createdAt: now,
      ));
      return verification;
    });
  }
}

class ApplySmsVerification {
  ApplySmsVerification({
    required this.verificationRepo,
    required this.outboxRepo,
    required this.gate,
    required this.clock,
    Uuid? uuid,
  }) : _uuid = uuid ?? Uuid();

  final SmsVerificationRepository verificationRepo;
  final SmsOutboxRepository outboxRepo;
  final MutationGate gate;
  final Clock clock;
  final Uuid _uuid;

  Future<SmsLearningProposal?> call({
    required String verificationId,
    int activationThreshold = 3,
  }) {
    return gate.run(() async {
      final verification =
          await verificationRepo.getVerification(verificationId);
      if (verification == null || verification.status != 'submitted') {
        return null;
      }

      final pattern = _normalizePattern(verification.body);
      final existing = await verificationRepo.findLearningProposal(
          verification.senderId, pattern);
      final now = clock.now();

      final proposal = existing == null
          ? SmsLearningProposal(
              id: _uuid.v4(),
              senderId: verification.senderId,
              normalizedPattern: pattern,
              corrections: verification.corrections,
              confirmationCount: 1,
              activationThreshold: activationThreshold,
              createdAt: now,
            )
          : SmsLearningProposal(
              id: existing.id,
              senderId: existing.senderId,
              normalizedPattern: existing.normalizedPattern,
              corrections: verification.corrections,
              confirmationCount: existing.confirmationCount + 1,
              activationThreshold: activationThreshold,
              status: existing.status,
              createdAt: existing.createdAt,
              activatedAt: existing.activatedAt,
            );

      if (existing == null) {
        await verificationRepo.insertLearningProposal(proposal);
      } else {
        await verificationRepo.updateLearningProposal(proposal);
      }

      SmsLearningProposal? activated;
      if (proposal.isSafeToActivate) {
        activated = SmsLearningProposal(
          id: proposal.id,
          senderId: proposal.senderId,
          normalizedPattern: proposal.normalizedPattern,
          corrections: proposal.corrections,
          confirmationCount: proposal.confirmationCount,
          activationThreshold: proposal.activationThreshold,
          status: 'active',
          createdAt: proposal.createdAt,
          activatedAt: now,
        );
        await verificationRepo.updateLearningProposal(activated);
      }

      await verificationRepo.updateVerification(
          verification.copyWith(status: 'applied', appliedAt: now));
      await outboxRepo.enqueueIfAbsent(SmsOutboxEvent(
        id: _uuid.v4(),
        eventType: SmsDomainEventNames.verificationApplied,
        aggregateId: verification.id,
        idempotencyKey: 'sms-verification-applied:${verification.id}',
        payload: {
          'verificationId': verification.id,
          'proposalId': proposal.id,
          'active': activated != null,
        },
        availableAt: now,
        createdAt: now,
      ));
      if (activated != null) {
        await outboxRepo.enqueueIfAbsent(SmsOutboxEvent(
          id: _uuid.v4(),
          eventType: SmsDomainEventNames.templateLearned,
          aggregateId: activated.id,
          idempotencyKey: 'sms-template-learned:${activated.id}',
          payload: {
            'proposalId': activated.id,
            'senderId': activated.senderId,
            'normalizedPattern': activated.normalizedPattern,
          },
          availableAt: now,
          createdAt: now,
        ));
      }
      return activated ?? proposal;
    });
  }

  String _normalizePattern(String body) {
    var normalized = body.toLowerCase();
    normalized = normalized.replaceAll(
        RegExp(r'\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b'), '<DATE>');
    normalized = normalized.replaceAll(
        RegExp(r'\b\d+(?:[.,]\d+)*(?:\.\d+)?\b'), '<NUM>');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }
}
