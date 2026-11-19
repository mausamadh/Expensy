// lib/domain/recurring/recurring_planner.dart
//
// Pure domain service for the Recurring bounded context (hexagonal
// architecture, HEXAGONAL_MIGRATION_PLAN.md §5 Phase 4).
//
// Encapsulates the recurring auto-pay planning rules that were previously
// inlined in `RecurringPaymentProcessor`: due-date gating, occurrence
// computation, the catch-up loop, debit-card balance redirection, and
// cross-currency transfer credit computation.
//
// The planner is dependency-free and deterministic: it produces a [RecurringStep]
// describing the next due occurrence's action (transactions, balance deltas,
// updated recurring row, and history entry). The adapter (the processor) is
// responsible for the DB transaction, idempotency check, and atomic write.
//
// No Flutter, Drift, or plugin imports (enforced by ci_guard).

import 'package:finwick/models/models.dart';

import '../fx/ports/exchange_rate_provider.dart';
import '../ledger/balance_delta.dart' show BalanceDeltaService;
import '../shared/uuid.dart' show Uuid;

/// Base type for a single planned recurring occurrence.
sealed class RecurringStep {
  const RecurringStep({
    required this.occurrence,
    required this.updatedRecurring,
    required this.historyEntry,
  });

  /// The exact DateTime of this occurrence (nextDate + autoPayTime).
  final DateTime occurrence;

  /// The recurring row after this payment (nextDate advanced, paidPayments+1).
  final RecurringPayment updatedRecurring;

  /// The history entry recording this payment.
  final RecurringHistoryEntry historyEntry;
}

/// A planned transfer occurrence (two legs + two balance deltas).
class TransferStep extends RecurringStep {
  const TransferStep({
    required super.occurrence,
    required super.updatedRecurring,
    required super.historyEntry,
    required this.outTx,
    required this.inTx,
    required this.fromDelta,
    required this.toDelta,
  });

  final AppTransaction outTx;
  final AppTransaction inTx;
  final double fromDelta;
  final double toDelta;
}

/// A planned single-leg payment occurrence (one transaction + one delta).
class PaymentStep extends RecurringStep {
  const PaymentStep({
    required super.occurrence,
    required super.updatedRecurring,
    required super.historyEntry,
    required this.tx,
    required this.balanceDelta,
  });

  final AppTransaction tx;
  final double balanceDelta;
}

/// Pure rules for recurring auto-pay planning.
class RecurringPaymentPlanner {
  RecurringPaymentPlanner({Uuid? uuid}) : _uuid = uuid ?? Uuid();

  final Uuid _uuid;
  final BalanceDeltaService _delta = const BalanceDeltaService();

  /// Checks if a payment is due based on nextDate, endDate, and autoPayTime.
  static bool isPaymentDue(RecurringPayment r, DateTime now) {
    if (!r.autoPayEnabled) return false;
    if (r.endDate != null && r.nextDate.isAfter(r.endDate!)) return false;

    final today = DateTime(now.year, now.month, now.day);
    final dueDate = DateTime(r.nextDate.year, r.nextDate.month, r.nextDate.day);

    if (dueDate.isBefore(today)) return true;
    if (dueDate.isAtSameMomentAs(today)) {
      final parts = r.autoPayTime.split(':');
      final targetHour = int.tryParse(parts[0]) ?? 9;
      final targetMinute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
      final currentMinutes = now.hour * 60 + now.minute;
      final targetMinutes = targetHour * 60 + targetMinute;
      return currentMinutes >= targetMinutes;
    }
    return false;
  }

  /// Calculates the exact DateTime occurrence for a given nextDate and autoPayTime.
  static DateTime occurrenceDateFor(RecurringPayment r) {
    final parts = r.autoPayTime.split(':');
    final hour = int.tryParse(parts[0]) ?? 9;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return DateTime(
      r.nextDate.year,
      r.nextDate.month,
      r.nextDate.day,
      hour,
      minute,
    );
  }

  /// Plans the next due occurrence for [r], or returns null when the payment
  /// is not due (or a transfer cannot be resolved) and the catch-up loop should
  /// stop.
  ///
  /// [accounts] is an id → Account lookup. [ratesProvider] is consulted only
  /// for cross-currency transfers lacking an explicit [RecurringPayment.toAmount].
  Future<RecurringStep?> planNextStep({
    required RecurringPayment r,
    required Map<String, Account> accounts,
    required DateTime now,
    required ExchangeRateProvider ratesProvider,
    String defaultCurrency = 'EGP',
  }) async {
    if (!isPaymentDue(r, now)) return null;

    final occurrence = occurrenceDateFor(r);

    if (r.isTransfer) {
      final toId = r.toAccountId;
      if (toId == null || toId.isEmpty || toId == r.accountId) return null;

      final fromAcc = accounts[r.accountId];
      final toAcc = accounts[toId];
      final fromBalId = (fromAcc != null &&
              fromAcc.isDebit &&
              fromAcc.linkedAccountId != null &&
              fromAcc.linkedAccountId!.isNotEmpty)
          ? fromAcc.linkedAccountId!
          : r.accountId;
      final toBalId = (toAcc != null &&
              toAcc.isDebit &&
              toAcc.linkedAccountId != null &&
              toAcc.linkedAccountId!.isNotEmpty)
          ? toAcc.linkedAccountId!
          : toId;
      if (fromBalId == toBalId) return null;

      final fromBalAcc = accounts[fromBalId] ?? fromAcc;
      final toBalAcc = accounts[toBalId] ?? toAcc;
      final fromCurrency = fromBalAcc?.currency ?? defaultCurrency;
      final toCurrency = toBalAcc?.currency ?? defaultCurrency;

      double? creditAmount;
      if (r.toAmount != null && r.toAmount! > 0) {
        creditAmount = r.toAmount!;
      } else if (fromCurrency == toCurrency) {
        creditAmount = r.amount;
      } else {
        final rates = await ratesProvider.getRates();
        if (rates.isNotEmpty) {
          creditAmount = _delta.convert(r.amount, fromCurrency, toCurrency, rates);
        }
      }
      if (creditAmount == null || creditAmount <= 0) return null;

      final transferGroupId = _uuid.v4();
      final outTx = AppTransaction(
        id: _uuid.v4(),
        type: 'expense',
        amount: r.amount,
        description: '${r.name} (Transfer out)',
        accountId: fromBalId,
        paidViaAccountId: fromBalId != r.accountId ? r.accountId : null,
        categoryId: 'sys_transfer',
        date: occurrence,
        note: r.notes,
        currency: fromCurrency,
        transferGroupId: transferGroupId,
      );
      final inTx = AppTransaction(
        id: _uuid.v4(),
        type: 'income',
        amount: creditAmount,
        description: '${r.name} (Transfer in)',
        accountId: toBalId,
        paidViaAccountId: toBalId != toId ? toId : null,
        categoryId: 'sys_transfer',
        date: occurrence,
        note: r.notes,
        currency: toCurrency,
        transferGroupId: transferGroupId,
      );

      final updatedR = r.copyWith(
        nextDate: r.calcNextDate(),
        paidPayments: r.paidPayments + 1,
      );

      final historyEntry = RecurringHistoryEntry(
        id: _uuid.v4(),
        recurringId: r.id,
        action: 'paid',
        date: occurrence,
        amount: r.amount,
        currency: fromCurrency,
      );

      return TransferStep(
        occurrence: occurrence,
        updatedRecurring: updatedR,
        historyEntry: historyEntry,
        outTx: outTx,
        inTx: inTx,
        fromDelta: -r.amount,
        toDelta: creditAmount,
      );
    }

    // Determine balance-holding account (Debit Card redirect)
    final acc = accounts[r.accountId];
    final balanceAccountId = (acc != null &&
            acc.isDebit &&
            acc.linkedAccountId != null &&
            acc.linkedAccountId!.isNotEmpty)
        ? acc.linkedAccountId!
        : r.accountId;
    final paidViaAccountId = (acc != null && acc.isDebit) ? r.accountId : null;
    final balAcc = accounts[balanceAccountId] ?? acc;
    final resolvedCurrency =
        balAcc?.currency ?? acc?.currency ?? defaultCurrency;

    final tx = AppTransaction(
      id: _uuid.v4(),
      type: r.paymentType,
      amount: r.amount,
      description: '${r.name} (recurring)',
      accountId: balanceAccountId,
      paidViaAccountId: paidViaAccountId,
      categoryId: r.categoryId,
      date: occurrence,
      currency: resolvedCurrency,
    );

    final balanceDelta = r.paymentType == 'income' ? r.amount : -r.amount;

    final updatedR = r.copyWith(
      nextDate: r.calcNextDate(),
      paidPayments: r.paidPayments + 1,
    );

    final historyEntry = RecurringHistoryEntry(
      id: _uuid.v4(),
      recurringId: r.id,
      action: 'paid',
      date: occurrence,
      amount: r.amount,
      currency: resolvedCurrency,
    );

    return PaymentStep(
      occurrence: occurrence,
      updatedRecurring: updatedR,
      historyEntry: historyEntry,
      tx: tx,
      balanceDelta: balanceDelta,
    );
  }
}
