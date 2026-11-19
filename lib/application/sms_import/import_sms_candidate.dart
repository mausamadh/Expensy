// lib/application/sms_import/import_sms_candidate.dart
//
// ImportSmsCandidate use case: turns a pending SMS inbox item into a ledger
// transaction (expense/income or transfer), always upserts a sender rule so
// the next message from the same sender auto-fills, and marks the item
// imported.
//
// Reads the in-memory inbox/rules (owned by the view model) and the
// account/category parallel lists (derived by the view model from the ledger
// context), and persists through the [SmsInboxRepository], [SmsRuleRepository]
// and [LedgerGateway] ports.

import 'package:finwick/application/mutation_gate.dart';
import 'package:finwick/domain/shared/clock.dart';
import 'package:finwick/domain/shared/uuid.dart';
import 'package:finwick/domain/sms_import/ports/ports.dart';
import 'package:finwick/domain/sms_import/sms_entities.dart';
import 'package:finwick/domain/sms_import/sms_rule_matcher.dart';

/// The outcome of a successful import: the ledger tx id and the updated inbox
/// item (so the view model can reassign its in-memory list).
class ImportSmsResult {
  const ImportSmsResult({required this.txId, required this.updatedItem});
  final String txId;
  final SmsInboxItem updatedItem;
}

class ImportSmsCandidate {
  ImportSmsCandidate({
    required this.inboxRepo,
    required this.ruleRepo,
    required this.ledger,
    required this.gate,
    required this.clock,
    Uuid? uuid,
    SmsRuleMatcher? matcher,
  })  : _uuid = uuid ?? Uuid(),
        _matcher = matcher ?? const SmsRuleMatcher();

  final SmsInboxRepository inboxRepo;
  final SmsRuleRepository ruleRepo;
  final LedgerGateway ledger;
  final MutationGate gate;
  final Clock clock;
  final Uuid _uuid;
  final SmsRuleMatcher _matcher;

  /// Returns null when the item is missing, not pending, or cannot be
  /// resolved to a valid account/category/amount.
  Future<ImportSmsResult?> call(
    String inboxId, {
    required List<SmsInboxItem> inbox,
    required List<SmsRule> rules,
    required List<String> accountIds,
    required List<String> accountTypes,
    required List<String> categoryIds,
    required List<String> categoryTypes,
    required List<bool> categoryIsSystem,
    String? type,
    double? amount,
    String? accountId,
    String? toAccountId,
    String? categoryId,
    String? description,
    DateTime? date,
  }) {
    return gate.run(() async {
      final item = inbox.firstWhereOrNull(inboxId);
      if (item == null || item.status != 'pending') return null;

      final rule = _matcher.matchRule(item, rules);
      final effType =
          type ?? rule?.transactionType ?? _matcher.typeFromParsed(item.parsedType);
      final effAccountId =
          accountId ?? rule?.accountId ?? _matcher.defaultAccountId(accountIds, accountTypes);
      final effCategoryId = categoryId ??
          rule?.categoryId ??
          _matcher.defaultCategoryId(effType, categoryIds, categoryTypes, categoryIsSystem);
      if (effAccountId.isEmpty || effCategoryId.isEmpty) return null;

      final effAmount =
          amount ?? _matcher.amountMajor(item.parsedAmountMinorUnits, item.parsedCurrency);
      if (effAmount <= 0) return null;

      final effDate = date ?? item.parsedDate ?? clock.now();
      final trimmedDesc = (description ?? '').trim();
      final effDesc = trimmedDesc.isNotEmpty ? trimmedDesc : (item.parsedMerchant ?? item.senderId);

      String? txId;
      if (effType == 'transfer') {
        final toId = (toAccountId != null && toAccountId.isNotEmpty)
            ? toAccountId
            : _matcher.transferToAccount(effAccountId, accountIds);
        if (toId != null && toId != effAccountId) {
          txId = await ledger.addTransfer(
            fromId: effAccountId,
            toId: toId,
            fromAmount: effAmount,
            title: effDesc,
            date: effDate,
          );
        }
      } else {
        txId = await ledger.addTransaction(
          id: _uuid.v4(),
          type: effType == 'income' ? 'income' : 'expense',
          amount: effAmount,
          description: effDesc,
          accountId: effAccountId,
          categoryId: effCategoryId,
          date: effDate,
          note: (item.parsedReference != null && item.parsedReference!.isNotEmpty)
              ? 'Ref: ${item.parsedReference}'
              : '',
        );
      }
      if (txId == null) return null;

      await _saveRuleFor(item, rules, effAccountId, effCategoryId, effType);

      final updated = item.copyWith(status: 'imported', importedTxId: txId);
      await inboxRepo.update(updated);
      return ImportSmsResult(txId: txId, updatedItem: updated);
    });
  }

  /// Always upserts a rule for the item's sender so future messages from the
  /// same sender auto-fill account/category/type.
  Future<void> _saveRuleFor(
    SmsInboxItem item,
    List<SmsRule> rules,
    String accountId,
    String categoryId,
    String type,
  ) async {
    final existing = _matcher.matchRule(item, rules);
    if (existing != null) {
      await ruleRepo.update(SmsRule(
        id: existing.id,
        senderId: existing.senderId,
        merchantPattern: existing.merchantPattern,
        accountId: accountId,
        categoryId: categoryId,
        transactionType: type,
        createdAt: existing.createdAt,
      ));
    } else {
      await ruleRepo.insert(SmsRule(
        id: _uuid.v4(),
        senderId: item.senderId,
        merchantPattern: item.parsedMerchant,
        accountId: accountId,
        categoryId: categoryId,
        transactionType: type,
        createdAt: clock.now(),
      ));
    }
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
