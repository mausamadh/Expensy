import 'package:collection/collection.dart';

import 'package:finwick/models/models.dart';
import 'package:finwick/domain/ledger/balance_delta.dart';
import 'package:finwick/domain/ledger/rates_unavailable_exception.dart';
import 'package:finwick/domain/ledger/ports/write_ports.dart';
import 'package:finwick/domain/shared/uuid.dart';

/// The provider's in-memory ledger state, passed into use cases so they can
/// compute balance deltas exactly as the provider did before the migration.
///
/// These use cases deliberately do NOT take a [MutationGate]: the provider
/// already serializes the whole mutation (use case + in-memory sync + side
/// effects) under its own mutex, so a second gate would be redundant.
class LedgerContext {
  const LedgerContext({
    required this.accountById,
    required this.settingsCurrency,
    required this.exchangeRates,
  });

  final AccountLookup accountById;
  final String settingsCurrency;
  final Map<String, double> exchangeRates;
}

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

class AddTransactionResult {
  const AddTransactionResult({
    required this.tx,
    required this.balanceAccountId,
    required this.delta,
    this.splits,
  });

  final AppTransaction tx;
  final String balanceAccountId;
  final double delta;
  final List<TransactionSplit>? splits;
}

class UpdateTransactionResult {
  const UpdateTransactionResult({
    required this.tx,
    required this.oldBalanceAccId,
    required this.newBalanceAccId,
    required this.oldDelta,
    required this.newDelta,
    this.splits,
  });

  final AppTransaction tx;
  final String oldBalanceAccId;
  final String newBalanceAccId;
  final double oldDelta;
  final double newDelta;
  final List<TransactionSplit>? splits;
}

/// A single balance reversal applied while deleting a transaction.
class BalanceReversal {
  const BalanceReversal({
    required this.transactionId,
    required this.accountId,
    required this.delta,
  });

  final String transactionId;
  final String accountId;
  final double delta;
}

class DeleteTransactionResult {
  const DeleteTransactionResult({
    required this.removedIds,
    required this.reversals,
    this.transferGroupId,
  });

  final Set<String> removedIds;
  final List<BalanceReversal> reversals;
  final String? transferGroupId;
}

class AddTransferResult {
  const AddTransferResult({
    required this.debit,
    required this.credit,
    required this.fromAccountId,
    required this.toAccountId,
    required this.fromDelta,
    required this.toDelta,
  });

  final AppTransaction debit;
  final AppTransaction credit;
  final String fromAccountId;
  final String toAccountId;
  final double fromDelta;
  final double toDelta;
}

// ---------------------------------------------------------------------------
// Transaction use cases
// ---------------------------------------------------------------------------

class AddTransaction {
  AddTransaction({
    required TransactionWriteRepository transactions,
    required BalanceDeltaService balance,
  })  : _tx = transactions,
        _balance = balance;

  final TransactionWriteRepository _tx;
  final BalanceDeltaService _balance;

  Future<AddTransactionResult> call(
    AppTransaction t,
    LedgerContext ctx, {
    List<TransactionSplit>? splits,
  }) async {
    final delta = _balance.txDelta(
      t,
      accountById: ctx.accountById,
      settingsCurrency: ctx.settingsCurrency,
      exchangeRates: ctx.exchangeRates,
      requireRates: true,
    );
    final balanceAccountId =
        _balance.balanceAccountIdFor(ctx.accountById(t.accountId), t.accountId);
    final normalizedCurrency = _balance.txCurrency(
      t,
      accountById: ctx.accountById,
      settingsCurrency: ctx.settingsCurrency,
    );
    final txToSave = balanceAccountId != t.accountId
        ? t.copyWith(
            accountId: balanceAccountId,
            paidViaAccountId: t.paidViaAccountId ?? t.accountId,
            currency: normalizedCurrency,
          )
        : (t.currency.isEmpty
              ? t.copyWith(currency: normalizedCurrency)
              : t);

    await _tx.applyTransactionWithBalance(txToSave, delta);

    List<TransactionSplit>? savedSplits;
    if (splits != null) {
      await _tx.saveTransactionSplits(txToSave.id, splits);
      savedSplits = splits;
    }

    return AddTransactionResult(
      tx: txToSave,
      balanceAccountId: balanceAccountId,
      delta: delta,
      splits: savedSplits,
    );
  }
}

class UpdateTransaction {
  UpdateTransaction({
    required TransactionWriteRepository transactions,
    required BalanceDeltaService balance,
  })  : _tx = transactions,
        _balance = balance;

  final TransactionWriteRepository _tx;
  final BalanceDeltaService _balance;

  Future<UpdateTransactionResult> call(
    AppTransaction updated,
    AppTransaction original,
    LedgerContext ctx, {
    List<TransactionSplit>? splits,
  }) async {
    final oldDelta = _balance.txDelta(
      original,
      accountById: ctx.accountById,
      settingsCurrency: ctx.settingsCurrency,
      exchangeRates: ctx.exchangeRates,
      reverse: true,
    );
    final newDelta = _balance.txDelta(
      updated,
      accountById: ctx.accountById,
      settingsCurrency: ctx.settingsCurrency,
      exchangeRates: ctx.exchangeRates,
      requireRates: true,
    );
    final oldBalanceAccId = _balance.balanceAccountIdFor(
      ctx.accountById(original.accountId),
      original.accountId,
    );
    final newBalanceAccId = _balance.balanceAccountIdFor(
      ctx.accountById(updated.accountId),
      updated.accountId,
    );
    final normalizedCurrency = _balance.txCurrency(
      updated,
      accountById: ctx.accountById,
      settingsCurrency: ctx.settingsCurrency,
    );
    final isTransferTx = original.isTransfer || updated.isTransfer;
    final enforcedUpdated = isTransferTx
        ? updated.copyWith(
            categoryId: 'sys_transfer',
            transferGroupId:
                original.transferGroupId ?? updated.transferGroupId,
          )
        : updated;
    final txToSave = newBalanceAccId != enforcedUpdated.accountId
        ? enforcedUpdated.copyWith(
            accountId: newBalanceAccId,
            paidViaAccountId:
                enforcedUpdated.paidViaAccountId ?? enforcedUpdated.accountId,
            currency: normalizedCurrency,
          )
        : (enforcedUpdated.currency.isEmpty
              ? enforcedUpdated.copyWith(currency: normalizedCurrency)
              : enforcedUpdated);

    await _tx.applyTransactionEdit(
      updated: txToSave,
      oldAccountId: oldBalanceAccId,
      oldDelta: oldDelta,
      newAccountId: newBalanceAccId,
      newDelta: newDelta,
    );

    List<TransactionSplit>? savedSplits;
    if (splits != null) {
      await _tx.saveTransactionSplits(txToSave.id, splits);
      savedSplits = splits;
    }

    return UpdateTransactionResult(
      tx: txToSave,
      oldBalanceAccId: oldBalanceAccId,
      newBalanceAccId: newBalanceAccId,
      oldDelta: oldDelta,
      newDelta: newDelta,
      splits: savedSplits,
    );
  }
}

class DeleteTransaction {
  DeleteTransaction({
    required TransactionWriteRepository transactions,
    required BalanceDeltaService balance,
  })  : _tx = transactions,
        _balance = balance;

  final TransactionWriteRepository _tx;
  final BalanceDeltaService _balance;

  Future<DeleteTransactionResult> call(
    String id,
    List<AppTransaction> transactions,
    LedgerContext ctx,
  ) async {
    final t = transactions.where((x) => x.id == id).firstOrNull;
    if (t != null) {
      if (t.transferGroupId != null && t.transferGroupId!.isNotEmpty) {
        final pair = transactions
            .where((tx) => tx.transferGroupId == t.transferGroupId)
            .toList();
        final reversals = <BalanceReversal>[];
        for (final member in pair) {
          final delta = _balance.txDelta(
            member,
            accountById: ctx.accountById,
            settingsCurrency: ctx.settingsCurrency,
            exchangeRates: ctx.exchangeRates,
            reverse: true,
          );
          final balAccId = _balance.balanceAccountIdFor(
            ctx.accountById(member.accountId),
            member.accountId,
          );
          await _tx.applyDeleteTransactionWithBalance(member.id, balAccId, delta);
          reversals.add(BalanceReversal(
            transactionId: member.id,
            accountId: balAccId,
            delta: delta,
          ));
        }
        return DeleteTransactionResult(
          removedIds: pair.map((e) => e.id).toSet(),
          reversals: reversals,
          transferGroupId: t.transferGroupId,
        );
      }

      final delta = _balance.txDelta(
        t,
        accountById: ctx.accountById,
        settingsCurrency: ctx.settingsCurrency,
        exchangeRates: ctx.exchangeRates,
        reverse: true,
      );
      final balAccId = _balance.balanceAccountIdFor(
        ctx.accountById(t.accountId),
        t.accountId,
      );
      await _tx.applyDeleteTransactionWithBalance(t.id, balAccId, delta);
      return DeleteTransactionResult(
        removedIds: {t.id},
        reversals: [
          BalanceReversal(transactionId: t.id, accountId: balAccId, delta: delta),
        ],
        transferGroupId: null,
      );
    }

    await _tx.deleteTransaction(id);
    return DeleteTransactionResult(
      removedIds: {id},
      reversals: const [],
      transferGroupId: null,
    );
  }
}

class AddTransfer {
  AddTransfer({
    required TransactionWriteRepository transactions,
    required BalanceDeltaService balance,
    Uuid? uuid,
  })  : _tx = transactions,
        _balance = balance,
        _uuid = uuid ?? Uuid();

  final TransactionWriteRepository _tx;
  final BalanceDeltaService _balance;
  final Uuid _uuid;

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

    final effFromId = _balance.balanceAccountIdFor(ctx.accountById(fromId), fromId);
    final effToId = _balance.balanceAccountIdFor(ctx.accountById(toId), toId);
    if (effFromId == effToId) return null;

    final fromAcc = ctx.accountById(effFromId);
    final toAcc = ctx.accountById(effToId);
    final fromCurrency = fromAcc?.currency ?? ctx.settingsCurrency;
    final toCurrency = toAcc?.currency ?? ctx.settingsCurrency;

    double creditAmount;
    if (toAmount != null && toAmount > 0) {
      creditAmount = toAmount;
    } else if (fromCurrency == toCurrency) {
      creditAmount = fromAmount;
    } else {
      if (ctx.exchangeRates.isEmpty) throw const RatesUnavailableException();
      final converted =
          _balance.convert(fromAmount, fromCurrency, toCurrency, ctx.exchangeRates);
      if (converted == null) throw const RatesUnavailableException();
      creditAmount = converted;
    }

    final txDate = date ?? DateTime.now();
    final catId = 'sys_transfer';
    final transferGroupId = _uuid.v4();
    final cleanTitle = title?.trim() ?? '';
    final outDesc = cleanTitle.isNotEmpty ? '$cleanTitle (Transfer out)' : 'Transfer out';
    final inDesc = cleanTitle.isNotEmpty ? '$cleanTitle (Transfer in)' : 'Transfer in';

    final debit = AppTransaction(
      id: _uuid.v4(),
      type: 'expense',
      amount: fromAmount,
      description: outDesc,
      accountId: effFromId,
      paidViaAccountId: effFromId != fromId ? fromId : null,
      categoryId: catId,
      date: txDate,
      note: note ?? '',
      currency: fromCurrency,
      transferGroupId: transferGroupId,
    );
    final credit = AppTransaction(
      id: _uuid.v4(),
      type: 'income',
      amount: creditAmount,
      description: inDesc,
      accountId: effToId,
      paidViaAccountId: effToId != toId ? toId : null,
      categoryId: catId,
      date: txDate,
      note: note ?? '',
      currency: toCurrency,
      transferGroupId: transferGroupId,
    );

    await _tx.applyTransferWithBalances(debit, credit, -fromAmount, creditAmount);

    return AddTransferResult(
      debit: debit,
      credit: credit,
      fromAccountId: effFromId,
      toAccountId: effToId,
      fromDelta: -fromAmount,
      toDelta: creditAmount,
    );
  }
}

class SaveTransactionSplits {
  SaveTransactionSplits({required TransactionWriteRepository transactions})
      : _tx = transactions;

  final TransactionWriteRepository _tx;

  Future<void> call(String transactionId, List<TransactionSplit> newSplits) async {
    await _tx.saveTransactionSplits(transactionId, newSplits);
  }
}

// ---------------------------------------------------------------------------
// Account use cases
// ---------------------------------------------------------------------------

class AddAccount {
  AddAccount({required AccountWriteRepository accounts}) : _accounts = accounts;

  final AccountWriteRepository _accounts;

  Future<void> call(Account a) async {
    await _accounts.insertAccount(a);
  }
}

class UpdateAccount {
  UpdateAccount({required AccountWriteRepository accounts}) : _accounts = accounts;

  final AccountWriteRepository _accounts;

  Future<void> call(Account a, Account? old) async {
    final balanceDelta = old != null ? (a.balance - old.balance) : null;
    await _accounts.updateAccount(a, balanceDelta: balanceDelta);
  }
}

class DeleteAccount {
  DeleteAccount({required AccountWriteRepository accounts}) : _accounts = accounts;

  final AccountWriteRepository _accounts;

  Future<void> call(String id) async {
    await _accounts.deleteAccountCascade(id);
  }
}

class RestoreAccountSnapshot {
  RestoreAccountSnapshot({required AccountWriteRepository accounts})
      : _accounts = accounts;

  final AccountWriteRepository _accounts;

  Future<void> call(
    Account account,
    List<AppTransaction> transactions,
    List<TransactionSplit> splits,
  ) async {
    await _accounts.restoreAccountSnapshot(account, transactions, splits);
  }
}
