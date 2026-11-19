// lib/presentation/viewmodels/transactions_view_model.dart
//
// Presentation-layer view model for the Ledger bounded context
// (Phase 6, "Slim the provider") — the user's transactions and their
// per-transaction splits.
//
// Owns the `transactions` and `splits` collections plus the per-transaction
// split cache (`_splitsByTxId`). Every mutation is delegated to the
// application-layer ledger use cases (AddTransaction, UpdateTransaction,
// DeleteTransaction, AddTransfer, SaveTransactionSplits) and serialized
// through the provider's zone-based mutation mutex so ledger writes stay
// atomic with the provider's own writes.
//
// Cross-cutting couplings are injected as functions rather than a provider
// reference, keeping this file free of any `providers/` or `database/`
// import:
//   * [patchAccountBalance] — atomic balance-delta application.
//   * [checkBudgetAlert] — post-mutation budget alert check.
//   * [updateHomeWidgets] — home-widget refresh after mutations.
//   * [recordNetWorthSnapshot] — net-worth snapshot after mutations.
//   * [serializeMutation] — the provider's zone-based mutation mutex.
//   * [ledgerContext] — the ledger context (accounts, categories, ...)
//     resolved at mutation time.
//
// Layering: this file lives in `presentation/` and imports only `domain/`,
// `models/`, and `application/` — never `adapters/` or `database/`. The
// use cases and repository are injected through the constructor by the
// composition root.

import 'package:flutter/foundation.dart';

import 'package:finwick/application/ledger/ledger_write_use_cases.dart';
import 'package:finwick/domain/ledger/ports/ports.dart';
import 'package:finwick/models/models.dart';

class TransactionsViewModel extends ChangeNotifier {
  TransactionsViewModel({
    required AddTransaction addTransaction,
    required UpdateTransaction updateTransaction,
    required DeleteTransaction deleteTransaction,
    required AddTransfer addTransfer,
    required SaveTransactionSplits saveTransactionSplits,
    required TransactionRepository transactionRepo,
    required LedgerContext Function() ledgerContext,
    required void Function(String accountId, double delta) patchAccountBalance,
    required Future<void> Function(AppTransaction t) checkBudgetAlert,
    required void Function() updateHomeWidgets,
    required Future<void> Function() recordNetWorthSnapshot,
    required Future<T> Function<T>(Future<T> Function()) serializeMutation,
  })  : _addTransaction = addTransaction,
        _updateTransaction = updateTransaction,
        _deleteTransaction = deleteTransaction,
        _addTransfer = addTransfer,
        _saveTransactionSplits = saveTransactionSplits,
        _transactionRepo = transactionRepo,
        _ledgerContext = ledgerContext,
        _patchAccountBalance = patchAccountBalance,
        _checkBudgetAlert = checkBudgetAlert,
        _updateHomeWidgets = updateHomeWidgets,
        _recordNetWorthSnapshot = recordNetWorthSnapshot,
        _serializeMutation = serializeMutation;

  final AddTransaction _addTransaction;
  final UpdateTransaction _updateTransaction;
  final DeleteTransaction _deleteTransaction;
  final AddTransfer _addTransfer;
  final SaveTransactionSplits _saveTransactionSplits;
  final TransactionRepository _transactionRepo;
  final LedgerContext Function() _ledgerContext;
  final void Function(String accountId, double delta) _patchAccountBalance;
  final Future<void> Function(AppTransaction t) _checkBudgetAlert;
  final void Function() _updateHomeWidgets;
  final Future<void> Function() _recordNetWorthSnapshot;
  final Future<T> Function<T>(Future<T> Function()) _serializeMutation;

  // ── State ──────────────────────────────────────────────────────────────
  List<AppTransaction> _transactions = [];
  List<TransactionSplit> _splits = [];
  Map<String, List<TransactionSplit>> _splitsByTxId = {};

  /// All transactions (newest first).
  List<AppTransaction> get transactions => _transactions;

  /// Replaces the transaction list (fresh-list reactivity rule: reassign,
  /// never mutate in place) and notifies listeners.
  set transactions(List<AppTransaction> next) {
    _transactions = next;
    notifyListeners();
  }

  /// All splits.
  List<TransactionSplit> get splits => _splits;

  /// Replaces the split list (fresh-list reactivity rule: reassign, never
  /// mutate in place), rebuilds the per-transaction split cache, and
  /// notifies listeners.
  set splits(List<TransactionSplit> next) {
    _splits = next;
    _rebuildSplitsCache();
    notifyListeners();
  }

  // ── Split cache ────────────────────────────────────────────────────────
  void _rebuildSplitsCache() {
    _splitsByTxId = {};
    for (final s in _splits) {
      _splitsByTxId.putIfAbsent(s.transactionId, () => []).add(s);
    }
  }

  /// Rebuilds the per-transaction split cache from [splits]. Public so the
  /// provider's delegating [rebuildSplitsCache] shim can refresh it.
  void rebuildSplitsCache() => _rebuildSplitsCache();

  bool isTransactionSplit(String txId) =>
      _splitsByTxId.containsKey(txId) && _splitsByTxId[txId]!.isNotEmpty;

  List<TransactionSplit> getSplits(String txId) =>
      _splitsByTxId[txId] ?? const [];

  Future<List<TransactionSplit>> getSplitsForTransaction(String transactionId) =>
      _transactionRepo.getSplitsForTransaction(transactionId);

  // ── In-memory helpers ──────────────────────────────────────────────────
  void _insertTransactionInMemory(AppTransaction t) {
    final next = List<AppTransaction>.from(_transactions);
    next.add(t);
    next.sort((a, b) => b.date.compareTo(a.date));
    transactions = next;
  }

  void _updateTransactionInMemory(AppTransaction t) {
    final next = List<AppTransaction>.from(_transactions);
    final idx = next.indexWhere((existing) => existing.id == t.id);
    if (idx != -1) {
      next[idx] = t;
      next.sort((a, b) => b.date.compareTo(a.date));
      transactions = next;
    } else {
      _insertTransactionInMemory(t);
    }
  }

  // ── Mutations ──────────────────────────────────────────────────────────
  Future<void> addTransaction(
    AppTransaction t, {
    List<TransactionSplit>? splits,
  }) async {
    await _serializeMutation(() async {
      final result = await _addTransaction(t, _ledgerContext(), splits: splits);
      if (splits != null) {
        this.splits = await _transactionRepo.getAllSplits();
      }

      _patchAccountBalance(result.balanceAccountId, result.delta);
      _insertTransactionInMemory(result.tx);

      notifyListeners();
      await _checkBudgetAlert(result.tx);
      _updateHomeWidgets();
      await _recordNetWorthSnapshot();
    });
  }

  Future<void> updateTransaction(
    AppTransaction updated,
    AppTransaction original, {
    List<TransactionSplit>? splits,
  }) async {
    await _serializeMutation(() async {
      final result = await _updateTransaction(
        updated,
        original,
        _ledgerContext(),
        splits: splits,
      );
      if (splits != null) {
        this.splits = await _transactionRepo.getAllSplits();
      }

      if (result.oldBalanceAccId == result.newBalanceAccId) {
        _patchAccountBalance(result.oldBalanceAccId,
            result.oldDelta + result.newDelta);
      } else {
        _patchAccountBalance(result.oldBalanceAccId, result.oldDelta);
        _patchAccountBalance(result.newBalanceAccId, result.newDelta);
      }

      _updateTransactionInMemory(result.tx);
      notifyListeners();
      await _checkBudgetAlert(result.tx);
      _updateHomeWidgets();
      await _recordNetWorthSnapshot();
    });
  }

  Future<void> deleteTransaction(String id) async {
    await _serializeMutation(() async {
      final result = await _deleteTransaction(id, _transactions, _ledgerContext());

      for (final r in result.reversals) {
        _patchAccountBalance(r.accountId, r.delta);
      }

      if (result.transferGroupId != null) {
        final groupId = result.transferGroupId!;
        transactions =
            transactions.where((tx) => tx.transferGroupId != groupId).toList();
        for (final removedId in result.removedIds) {
          splits = splits.where((s) => s.transactionId != removedId).toList();
          _splitsByTxId.remove(removedId);
        }
      } else {
        splits = splits.where((s) => s.transactionId != id).toList();
        _splitsByTxId.remove(id);
        transactions = transactions.where((tx) => tx.id != id).toList();
      }

      notifyListeners();
      _updateHomeWidgets();
      await _recordNetWorthSnapshot();
    });
  }

  Future<AppTransaction?> addTransfer({
    required String fromId,
    required String toId,
    required double fromAmount,
    double? toAmount,
    String note = '',
    String? title,
    DateTime? date,
  }) async {
    if (fromId == toId || fromAmount <= 0) return null;
    return await _serializeMutation<AppTransaction?>(() async {
      final result = await _addTransfer(
        fromId: fromId,
        toId: toId,
        fromAmount: fromAmount,
        toAmount: toAmount,
        note: note,
        title: title,
        date: date,
        ctx: _ledgerContext(),
      );
      if (result == null) return null;

      _patchAccountBalance(result.fromAccountId, result.fromDelta);
      _patchAccountBalance(result.toAccountId, result.toDelta);
      _insertTransactionInMemory(result.debit);
      _insertTransactionInMemory(result.credit);

      notifyListeners();
      _updateHomeWidgets();
      await _recordNetWorthSnapshot();
      return result.debit;
    });
  }

  Future<void> saveTransactionSplits(
      String transactionId, List<TransactionSplit> newSplits) async {
    await _serializeMutation(() async {
      await _saveTransactionSplits(transactionId, newSplits);
      splits = await _transactionRepo.getAllSplits();
      notifyListeners();
    });
  }
}
