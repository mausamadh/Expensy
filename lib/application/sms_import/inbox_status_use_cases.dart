// lib/application/sms_import/inbox_status_use_cases.dart
//
// Use cases that change the status of a single SMS inbox item:
//   - DeclineSmsMessage  -> status 'dismissed'
//   - RestoreSmsCandidate -> status 'pending'
//   - DeleteSmsCandidate  -> hard delete
//
// Each reads the in-memory inbox (owned by the view model), persists the
// change through the [SmsInboxRepository] port, and returns the updated item
// (or the id to remove) so the view model can reassign its in-memory list
// with a fresh instance (AGENTS.md rule 6).

import 'package:finwick/application/mutation_gate.dart';
import 'package:finwick/domain/sms_import/ports/ports.dart';
import 'package:finwick/domain/sms_import/sms_entities.dart';

/// Marks an inbox item as dismissed (declined).
class DeclineSmsMessage {
  DeclineSmsMessage({required this.inboxRepo, required this.gate});

  final SmsInboxRepository inboxRepo;
  final MutationGate gate;

  /// Returns the updated item, or null if the item was not found.
  Future<SmsInboxItem?> call(String inboxId, {required List<SmsInboxItem> inbox}) {
    return gate.run(() async {
      final item = inbox.firstWhereOrNull(inboxId);
      if (item == null) return null;
      final updated = item.copyWith(status: 'dismissed');
      await inboxRepo.update(updated);
      return updated;
    });
  }
}

/// Restores a dismissed inbox item back to pending.
class RestoreSmsCandidate {
  RestoreSmsCandidate({required this.inboxRepo, required this.gate});

  final SmsInboxRepository inboxRepo;
  final MutationGate gate;

  /// Returns the updated item, or null if the item was not found.
  Future<SmsInboxItem?> call(String inboxId, {required List<SmsInboxItem> inbox}) {
    return gate.run(() async {
      final item = inbox.firstWhereOrNull(inboxId);
      if (item == null) return null;
      final updated = item.copyWith(status: 'pending');
      await inboxRepo.update(updated);
      return updated;
    });
  }
}

/// Hard-deletes an inbox item.
class DeleteSmsCandidate {
  DeleteSmsCandidate({required this.inboxRepo, required this.gate});

  final SmsInboxRepository inboxRepo;
  final MutationGate gate;

  /// Returns the deleted id (so the view model can filter it out).
  Future<String> call(String inboxId) {
    return gate.run(() async {
      await inboxRepo.delete(inboxId);
      return inboxId;
    });
  }
}

extension on List<SmsInboxItem> {
  SmsInboxItem? firstWhereOrNull(String id) {
    for (final i in this) {
      if (i.id == id) return i;
    }
    return null;
  }
}
