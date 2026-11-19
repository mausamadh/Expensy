// lib/services/recurring_payment_processor.dart
// note: Shared recurring payment processor for both foreground AppProvider and background Workmanager worker.
//
// Hexagonal (Phase 4): the pure planning rules (due-date gating, catch-up,
// debit-card redirect, cross-currency transfer) live in the domain
// `RecurringPaymentPlanner`. This adapter keeps the DB transaction, the
// idempotency check, and the atomic write, and exposes the same public API
// (constructor over [AppDatabase], `processDuePayments`, `isPaymentDue`,
// `occurrenceDateFor`, `hasHistoryForDate`) so the provider, the workmanager
// worker, and the tests are unchanged.

import '../adapters/fx/http_exchange_rate_provider.dart';
import '../database/app_database.dart';
import '../domain/fx/ports/exchange_rate_provider.dart';
import '../domain/recurring/recurring_planner.dart';
import '../models/models.dart';

class RecurringPaymentProcessor {
  final AppDatabase db;
  final RecurringPaymentPlanner _planner;

  RecurringPaymentProcessor(this.db, {RecurringPaymentPlanner? planner})
      : _planner = planner ?? RecurringPaymentPlanner();

  /// Checks if a payment is due based on nextDate, endDate, and autoPayTime.
  static bool isPaymentDue(RecurringPayment r, DateTime now) =>
      RecurringPaymentPlanner.isPaymentDue(r, now);

  /// Calculates the exact DateTime occurrence for a given nextDate and autoPayTime.
  static DateTime occurrenceDateFor(RecurringPayment r) =>
      RecurringPaymentPlanner.occurrenceDateFor(r);

  /// Processes all due recurring payments with auto-pay enabled.
  /// Runs inside a database transaction per payment for idempotency and atomicity.
  /// Handles debit-card balance redirection to parent bank account.
  Future<List<String>> processDuePayments({
    DateTime? nowOverride,
    String defaultCurrency = 'EGP',
  }) async {
    final now = nowOverride ?? DateTime.now();
    final recurringList = await db.getRecurring();
    final accountsList = await db.getAccounts();
    final processedIds = <String>[];

    // Build account lookup
    final accountMap = {for (final a in accountsList) a.id: a};

    // Cross-currency transfers consult the live rate cache (adapter concern).
    final ExchangeRateProvider ratesProvider = HttpExchangeRateProvider();

    for (var r in recurringList) {
      if (!r.autoPayEnabled) continue;

      int catchUpCycles = 0;
      const maxCycles = 24;

      while (catchUpCycles < maxCycles) {
        final step = await _planner.planNextStep(
          r: r,
          accounts: accountMap,
          now: now,
          ratesProvider: ratesProvider,
          defaultCurrency: defaultCurrency,
        );
        if (step == null) break;

        final updatedR = step.updatedRecurring;
        final historyEntry = step.historyEntry;
        final occurrence = step.occurrence;
        final transfer = step is TransferStep ? step : null;
        final payment = step is PaymentStep ? step : null;

        // Execute idempotency check and payment atomically inside a DB transaction
        final didPay = await db.transaction(() async {
          final alreadyPaid = await hasHistoryForDate(
            r.id,
            occurrence,
            action: 'paid',
          );
          if (alreadyPaid) {
            return false;
          }
          if (transfer != null) {
            await db.applyTransferWithBalances(
              transfer.outTx,
              transfer.inTx,
              transfer.fromDelta,
              transfer.toDelta,
            );
          } else if (payment != null) {
            await db.applyTransactionWithBalance(
                payment.tx, payment.balanceDelta);
          }
          await db.insertRecurringHistory(historyEntry);
          await db.updateRecurring(updatedR);
          return true;
        });

        if (!didPay) {
          // If already paid by another runner, step cursor and break/continue
          r = r.copyWith(nextDate: r.calcNextDate());
          break;
        }

        processedIds.add(r.id);
        r = updatedR;
        catchUpCycles++;

        if (r.endDate != null && r.nextDate.isAfter(r.endDate!)) break;
      }
    }

    return processedIds;
  }

  /// Checks whether a recurring history entry already exists on the calendar day
  /// of [occurrence]. If [action] is specified, matches only that action ('paid'|'skipped').
  Future<bool> hasHistoryForDate(
    String recurringId,
    DateTime occurrence, {
    String? action,
  }) async {
    final startOfDay =
        DateTime(occurrence.year, occurrence.month, occurrence.day);
    final endOfDay = DateTime(
        occurrence.year, occurrence.month, occurrence.day, 23, 59, 59, 999);

    final history = await db.getRecurringHistory(recurringId);
    return history.any((h) =>
        (action == null || h.action == action) &&
        !h.date.isBefore(startOfDay) &&
        !h.date.isAfter(endOfDay));
  }
}
