// test/helpers/transactions_test_harness.dart
//
// Shared widget-test harness for the Ledger (transactions) view model
// (Phase 6).
//
// Screens that read the delegated `transactions` / `splits` collections (or
// the derived split cache) watch `TransactionsViewModel`. Widget tests that
// mount those screens must therefore provide a `TransactionsViewModel` in
// addition to `AppProvider`. This helper builds a VM backed by in-memory
// fakes (no DB) and wraps a child in a `MultiProvider` exposing both
// notifiers.
//
// The ledger write use cases are faked to return canned results, and the
// cross-cutting hooks are no-ops (no DB, no net-worth snapshots, no
// notifications), so ledger mutations run against the in-memory state only.

import 'package:finwick/application/ledger/ledger_write_use_cases.dart';
import 'package:finwick/domain/ledger/ports/ports.dart';
import 'package:finwick/models/models.dart';
import 'package:finwick/presentation/viewmodels/transactions_view_model.dart';
import 'package:finwick/providers/app_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// In-memory [TransactionRepository] for widget tests — no DB access.
class InMemoryTransactionRepository implements TransactionRepository {
  List<AppTransaction> _transactions = [];
  List<TransactionSplit> _splits = [];

  @override
  Future<List<AppTransaction>> getAll({int? limit, int offset = 0}) async =>
      List.unmodifiable(_transactions);

  @override
  Future<List<AppTransaction>> getByAccount(
    String accountId, {
    int? limit,
    int offset = 0,
  }) async =>
      List.unmodifiable(
          _transactions.where((t) => t.accountId == accountId));

  @override
  Future<List<TransactionSplit>> getAllSplits() async =>
      List.unmodifiable(_splits);

  @override
  Future<List<TransactionSplit>> getSplitsForTransaction(
          String transactionId) async =>
      List.unmodifiable(
          _splits.where((s) => s.transactionId == transactionId));
}

/// Fake [AddTransaction] that echoes the input back as the saved transaction.
class FakeAddTransaction implements AddTransaction {
  @override
  Future<AddTransactionResult> call(
    AppTransaction t,
    LedgerContext ctx, {
    List<TransactionSplit>? splits,
  }) async {
    return AddTransactionResult(
      tx: t,
      balanceAccountId: t.accountId,
      delta: t.type == 'income' ? t.amount : -t.amount,
      splits: splits,
    );
  }
}

/// Fake [UpdateTransaction] that echoes the updated transaction back.
class FakeUpdateTransaction implements UpdateTransaction {
  @override
  Future<UpdateTransactionResult> call(
    AppTransaction updated,
    AppTransaction original,
    LedgerContext ctx, {
    List<TransactionSplit>? splits,
  }) async {
    return UpdateTransactionResult(
      tx: updated,
      oldBalanceAccId: original.accountId,
      newBalanceAccId: updated.accountId,
      oldDelta: original.type == 'income' ? -original.amount : original.amount,
      newDelta: updated.type == 'income' ? updated.amount : -updated.amount,
      splits: splits,
    );
  }
}

/// Fake [DeleteTransaction] that reports the deleted id with no reversals.
class FakeDeleteTransaction implements DeleteTransaction {
  @override
  Future<DeleteTransactionResult> call(
    String id,
    List<AppTransaction> transactions,
    LedgerContext ctx,
  ) async {
    return DeleteTransactionResult(
      removedIds: {id},
      reversals: const [],
      transferGroupId: null,
    );
  }
}

/// Fake [AddTransfer] that builds the debit/credit pair in memory.
class FakeAddTransfer implements AddTransfer {
  int _seq = 0;

  @override
  Future<AddTransferResult?> call({
    required String fromId,
    required String toId,
    required double fromAmount,
    double? toAmount,
    String? note,
    String? title,
    DateTime? date,
    required LedgerContext ctx,
  }) async {
    if (fromId == toId || fromAmount <= 0) return null;
    _seq++;
    final groupId = 'transfer-group-test-$_seq';
    final txDate = date ?? DateTime.now();
    final creditAmount = toAmount ?? fromAmount;
    final debit = AppTransaction(
      id: 'transfer-debit-test-$_seq',
      type: 'expense',
      amount: fromAmount,
      description: 'Transfer out',
      accountId: fromId,
      categoryId: 'sys_transfer',
      date: txDate,
      note: note ?? '',
      transferGroupId: groupId,
    );
    final credit = AppTransaction(
      id: 'transfer-credit-test-$_seq',
      type: 'income',
      amount: creditAmount,
      description: 'Transfer in',
      accountId: toId,
      categoryId: 'sys_transfer',
      date: txDate,
      note: note ?? '',
      transferGroupId: groupId,
    );
    return AddTransferResult(
      debit: debit,
      credit: credit,
      fromAccountId: fromId,
      toAccountId: toId,
      fromDelta: -fromAmount,
      toDelta: creditAmount,
    );
  }
}

/// Fake [SaveTransactionSplits] that is a no-op (the in-memory split list is
/// refreshed from the repository by the view model).
class FakeSaveTransactionSplits implements SaveTransactionSplits {
  @override
  Future<void> call(String transactionId, List<TransactionSplit> newSplits) async {}
}

/// Builds a [TransactionsViewModel] backed by in-memory fakes.
///
/// The cross-cutting hooks are no-ops in tests (no DB, no net-worth
/// snapshots, no notifications), so ledger mutations run against the
/// in-memory state only.
TransactionsViewModel buildTransactionsViewModel() => TransactionsViewModel(
      addTransaction: FakeAddTransaction(),
      updateTransaction: FakeUpdateTransaction(),
      deleteTransaction: FakeDeleteTransaction(),
      addTransfer: FakeAddTransfer(),
      saveTransactionSplits: FakeSaveTransactionSplits(),
      transactionRepo: InMemoryTransactionRepository(),
      ledgerContext: () => LedgerContext(
            accountById: (id) => null,
            settingsCurrency: 'NPR',
            exchangeRates: const {},
          ),
      patchAccountBalance: (accountId, delta) {},
      checkBudgetAlert: (t) async {},
      updateHomeWidgets: () {},
      recordNetWorthSnapshot: () async {},
      serializeMutation: <T>(Future<T> Function() action) => action(),
    );

/// Wraps [child] in a `MultiProvider` exposing [app] and a fresh
/// [TransactionsViewModel], so screens that watch the transactions view model
/// (e.g. the transactions/home/insights/statistics/calendar/backup/export
/// screens) resolve it in tests.
///
/// The view model is wired into [app] first, so data assigned through the
/// provider's delegating setter (`app.transactions = ...`) lands in the view
/// model and its listeners fire.
Widget wrapWithTransactions(AppProvider app, Widget child) {
  final vm = buildTransactionsViewModel();
  app.wireTransactionsVm(vm);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppProvider>.value(value: app),
      ChangeNotifierProvider<TransactionsViewModel>.value(value: vm),
    ],
    child: child,
  );
}
