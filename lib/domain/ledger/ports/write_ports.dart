// lib/domain/ledger/ports/write_ports.dart
//
// Write-side ports for the Ledger bounded context (hexagonal architecture,
// HEXAGONAL_MIGRATION_PLAN.md §5 Phase 2b).
//
// Domain-owned interfaces for the atomic balance-mutating writes. The
// application layer programs against these; Drift adapters
// (lib/adapters/ledger/) provide the concrete implementations over the
// existing AppDatabase. No Flutter, Drift, or plugin imports here (enforced
// by ci_guard).
//
// All balance mutations go through the atomic delta methods (AGENTS.md rule 3):
// the database applies the transaction insert/update/delete and the account
// balance delta in a single transaction, never via read-modify-write.

import 'package:finwick/models/models.dart';

/// Write access to transactions with atomic balance updates.
abstract interface class TransactionWriteRepository {
  /// Inserts [t] and applies [balanceDelta] to its balance account atomically.
  Future<void> applyTransactionWithBalance(
    AppTransaction t,
    double balanceDelta,
  );

  /// Applies an edit: reverses [oldDelta] on [oldAccountId], applies [newDelta]
  /// to [newAccountId], and updates the transaction row to [updated] — all in
  /// one transaction.
  Future<void> applyTransactionEdit({
    required AppTransaction updated,
    required String oldAccountId,
    required double oldDelta,
    required String newAccountId,
    required double newDelta,
  });

  /// Deletes the transaction [id] and applies [balanceDelta] (the reversed
  /// delta) to [accountId] atomically.
  Future<void> applyDeleteTransactionWithBalance(
    String id,
    String accountId,
    double balanceDelta,
  );

  /// Inserts both legs of a transfer and applies the two balance deltas
  /// atomically.
  Future<void> applyTransferWithBalances(
    AppTransaction outTx,
    AppTransaction inTx,
    double fromAccountDelta,
    double toAccountDelta,
  );

  /// Replaces all split lines for [transactionId].
  Future<void> saveTransactionSplits(
    String transactionId,
    List<TransactionSplit> splits,
  );

  /// Deletes a transaction row without touching balances (used when the
  /// transaction is not present in memory, e.g. stale ids).
  Future<void> deleteTransaction(String id);
}

/// Write access to accounts.
abstract interface class AccountWriteRepository {
  /// Inserts a new account.
  Future<void> insertAccount(Account a);

  /// Updates an account, optionally applying [balanceDelta] atomically.
  Future<void> updateAccount(Account a, {double? balanceDelta});

  /// Deletes an account and cascades to its transactions and splits.
  Future<void> deleteAccountCascade(String accountId);

  /// Applies a balance delta to an account without a transaction.
  Future<void> applyBalanceDelta(String accountId, double delta);

  /// Restores an account snapshot with its transactions and splits (used by
  /// undo/redo and backup restore).
  Future<void> restoreAccountSnapshot(
    Account account,
    List<AppTransaction> transactions,
    List<TransactionSplit> splits,
  );
}

/// Write access to categories.
abstract interface class CategoryWriteRepository {
  /// Inserts a new category.
  Future<void> insertCategory(AppCategory c);

  /// Updates an existing category.
  Future<void> updateCategory(AppCategory c);

  /// Deletes a category.
  Future<void> deleteCategory(String id);
}
