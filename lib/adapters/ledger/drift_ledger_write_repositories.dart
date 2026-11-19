// lib/adapters/ledger/drift_ledger_write_repositories.dart
//
// Drift-backed write adapters for the Ledger bounded context (Phase 2b).
//
// Thin wrappers over the existing [DBHelper] statics (which delegate to
// [AppDatabase.instance]) — no SQL changes. All balance mutations flow
// through the atomic delta methods (AGENTS.md rule 3).

import 'package:finwick/database/db_helper.dart';
import 'package:finwick/domain/ledger/ports/write_ports.dart';
import 'package:finwick/models/models.dart';

class DriftTransactionWriteRepository implements TransactionWriteRepository {
  const DriftTransactionWriteRepository();

  @override
  Future<void> applyTransactionWithBalance(
          AppTransaction t, double balanceDelta) =>
      DBHelper.applyTransactionWithBalance(t, balanceDelta);

  @override
  Future<void> applyTransactionEdit({
    required AppTransaction updated,
    required String oldAccountId,
    required double oldDelta,
    required String newAccountId,
    required double newDelta,
  }) =>
      DBHelper.applyTransactionEdit(
        updated: updated,
        oldAccountId: oldAccountId,
        oldDelta: oldDelta,
        newAccountId: newAccountId,
        newDelta: newDelta,
      );

  @override
  Future<void> applyDeleteTransactionWithBalance(
          String id, String accountId, double balanceDelta) =>
      DBHelper.applyDeleteTransactionWithBalance(id, accountId, balanceDelta);

  @override
  Future<void> applyTransferWithBalances(
    AppTransaction outTx,
    AppTransaction inTx,
    double fromAccountDelta,
    double toAccountDelta,
  ) =>
      DBHelper.applyTransferWithBalances(
          outTx, inTx, fromAccountDelta, toAccountDelta);

  @override
  Future<void> saveTransactionSplits(
          String transactionId, List<TransactionSplit> splits) =>
      DBHelper.saveTransactionSplits(transactionId, splits);

  @override
  Future<void> deleteTransaction(String id) => DBHelper.deleteTransaction(id);
}

class DriftAccountWriteRepository implements AccountWriteRepository {
  const DriftAccountWriteRepository();

  @override
  Future<void> insertAccount(Account a) => DBHelper.insertAccount(a);

  @override
  Future<void> updateAccount(Account a, {double? balanceDelta}) =>
      DBHelper.updateAccount(a, balanceDelta: balanceDelta);

  @override
  Future<void> deleteAccountCascade(String accountId) =>
      DBHelper.deleteAccountCascade(accountId);

  @override
  Future<void> applyBalanceDelta(String accountId, double delta) =>
      DBHelper.applyBalanceDelta(accountId, delta);

  @override
  Future<void> restoreAccountSnapshot(
    Account account,
    List<AppTransaction> transactions,
    List<TransactionSplit> splits,
  ) =>
      DBHelper.restoreAccountSnapshot(account, transactions, splits);
}

class DriftCategoryWriteRepository implements CategoryWriteRepository {
  const DriftCategoryWriteRepository();

  @override
  Future<void> insertCategory(AppCategory c) => DBHelper.insertCategory(c);

  @override
  Future<void> updateCategory(AppCategory c) => DBHelper.updateCategory(c);

  @override
  Future<void> deleteCategory(String id) => DBHelper.deleteCategory(id);
}
