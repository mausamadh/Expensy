// lib/application/sms_import/rule_use_cases.dart
//
// Use cases for user-confirmed routing rules:
//   - SaveSmsRule: upserts a rule keyed by (senderId, merchantPattern).
//   - DeleteSmsRule: hard-deletes a rule by id.
//
// Both persist through the [SmsRuleRepository] port and return the updated
// rule list (or the deleted id) so the view model can reassign its in-memory
// list with a fresh instance (AGENTS.md rule 6).

import 'package:finwick/application/mutation_gate.dart';
import 'package:finwick/domain/shared/clock.dart';
import 'package:finwick/domain/shared/uuid.dart';
import 'package:finwick/domain/sms_import/ports/ports.dart';
import 'package:finwick/domain/sms_import/sms_entities.dart';

/// Upserts a rule for a sender. An existing rule with the same sender and
/// (trimmed) merchant pattern is updated in place; otherwise a new rule is
/// inserted. Distinct patterns for the same sender stay separate.
class SaveSmsRule {
  SaveSmsRule({
    required this.ruleRepo,
    required this.gate,
    required this.clock,
    Uuid? uuid,
  }) : _uuid = uuid ?? Uuid();

  final SmsRuleRepository ruleRepo;
  final MutationGate gate;
  final Clock clock;
  final Uuid _uuid;

  /// Returns the updated rule list.
  Future<List<SmsRule>> call({
    required String senderId,
    required String merchantPattern,
    required String accountId,
    required String categoryId,
    required String transactionType,
    required List<SmsRule> rules,
  }) {
    return gate.run(() async {
      final pattern = merchantPattern.trim();
      SmsRule? existing;
      for (final r in rules) {
        if (r.senderId == senderId && (r.merchantPattern ?? '').trim() == pattern) {
          existing = r;
          break;
        }
      }
      if (existing != null) {
        final updated = SmsRule(
          id: existing.id,
          senderId: existing.senderId,
          merchantPattern: existing.merchantPattern,
          accountId: accountId,
          categoryId: categoryId,
          transactionType: transactionType,
          createdAt: existing.createdAt,
        );
        await ruleRepo.update(updated);
        return [for (final r in rules) r.id == updated.id ? updated : r];
      }
      final created = SmsRule(
        id: _uuid.v4(),
        senderId: senderId,
        merchantPattern: pattern,
        accountId: accountId,
        categoryId: categoryId,
        transactionType: transactionType,
        createdAt: clock.now(),
      );
      await ruleRepo.insert(created);
      return [...rules, created];
    });
  }
}

/// Hard-deletes a rule by id.
class DeleteSmsRule {
  DeleteSmsRule({required this.ruleRepo, required this.gate});

  final SmsRuleRepository ruleRepo;
  final MutationGate gate;

  /// Returns the deleted id.
  Future<String> call(String ruleId) {
    return gate.run(() async {
      await ruleRepo.delete(ruleId);
      return ruleId;
    });
  }
}
