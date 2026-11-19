// lib/presentation/viewmodels/loans_view_model.dart
//
// Presentation-layer view model for the Loans bounded context (Phase 6,
// "Slim the provider") — personal loans the user has taken (with an
// amortization schedule) and the individual installment payments that form
// each loan's ledger history.
//
// Owns the two state slices (`loans`, `loanPayments`) and delegates every
// mutation to the [LoanRepository] port. Replaces the loans slice of
// `AppProvider`.
//
// Cross-cutting couplings are injected as functions rather than a provider
// reference, keeping this file free of any `providers/` import:
//   * [applyAccountBalanceDelta] — the provider's atomic account-balance
//     delta (resolves a debit card to its linked account, applies the SQL
//     delta, and patches the in-memory account list), used to reverse/apply
//     principal transfers and installment debits.
//   * [onNetWorthChanged] — net-worth snapshot hook, fired after mutations.
//   * [serializeMutation] — the provider's zone-based mutation mutex, so
//     loan balance mutations serialize with the provider's own writes.
//
// Layering: this file lives in `presentation/` and imports only `domain/`,
// `models/`, and `services/` — never `adapters/` or `database/`. The
// repository is injected through the constructor by the composition root.
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'package:finwick/domain/loans/ports/loan_repository.dart';
import 'package:finwick/domain/shared/uuid.dart';
import 'package:finwick/models/models.dart';
import 'package:finwick/services/loan_reminder_service.dart';

class LoansViewModel extends ChangeNotifier {
  LoansViewModel({
    required LoanRepository repository,
    required Future<void> Function(String accountId, double delta)
        applyAccountBalanceDelta,
    required Future<void> Function() onNetWorthChanged,
    required Future<T> Function<T>(Future<T> Function()) serializeMutation,
  })  : _repo = repository,
        _applyAccountBalanceDelta = applyAccountBalanceDelta,
        _onNetWorthChanged = onNetWorthChanged,
        _serializeMutation = serializeMutation,
        _uuid = Uuid();

  final LoanRepository _repo;
  final Future<void> Function(String accountId, double delta)
      _applyAccountBalanceDelta;
  final Future<void> Function() _onNetWorthChanged;
  final Future<T> Function<T>(Future<T> Function()) _serializeMutation;
  final Uuid _uuid;
  final LoanReminderService _loanNotif = LoanReminderService();

  // ── State ──────────────────────────────────────────────────────────────
  List<Loan> _loans = [];
  List<LoanPayment> _loanPayments = [];

  /// All loans (creation order, oldest first per the DB query).
  List<Loan> get loans => _loans;

  /// Replaces the loans list (fresh-list reactivity rule: reassign, never
  /// mutate in place) and notifies listeners.
  set loans(List<Loan> next) {
    _loans = next;
    notifyListeners();
  }

  /// All loan payments (date, newest first per the DB query).
  List<LoanPayment> get loanPayments => _loanPayments;

  /// Replaces the loan-payments list and notifies listeners.
  set loanPayments(List<LoanPayment> next) {
    _loanPayments = next;
    notifyListeners();
  }

  // ── Loan mutations ─────────────────────────────────────────────────────
  Future<void> addLoan(Loan l) async {
    await _serializeMutation(() async {
      await _repo.insertLoan(l);
      if (l.transferAccountId != null) {
        await _applyAccountBalanceDelta(l.transferAccountId!, l.principal);
      }
      loans = await _repo.getLoans();
      await _onNetWorthChanged();
      if (l.reminderEnabled) await _loanNotif.scheduleReminder(l);
    });
  }

  Future<void> updateLoan(Loan l) async {
    await _serializeMutation(() async {
      await _loanNotif.cancelReminder(l.id);
      final oldL = _loans.firstWhere((x) => x.id == l.id);

      // Reverse old principal transfer if any
      if (oldL.transferAccountId != null) {
        await _applyAccountBalanceDelta(oldL.transferAccountId!, -oldL.principal);
      }
      // Apply new principal transfer if any
      if (l.transferAccountId != null) {
        await _applyAccountBalanceDelta(l.transferAccountId!, l.principal);
      }

      await _repo.updateLoan(l);
      loans = await _repo.getLoans();
      await _onNetWorthChanged();
      if (l.reminderEnabled) await _loanNotif.scheduleReminder(l);
    });
  }

  Future<void> deleteLoan(String id) async {
    await _serializeMutation(() async {
      await _loanNotif.cancelReminder(id);
      final l = _loans.firstWhere((x) => x.id == id);

      // Reverse principal transfer if any
      if (l.transferAccountId != null) {
        await _applyAccountBalanceDelta(l.transferAccountId!, -l.principal);
      }

      for (final p in loanPaymentsFor(id)) {
        if (p.accountId != null) {
          await _applyAccountBalanceDelta(p.accountId!, p.amount); // reverse debit
        }
      }
      await _repo.deleteLoan(id);
      loans = await _repo.getLoans();
      loanPayments = await _repo.getAllLoanPayments();
      await _onNetWorthChanged();
    });
  }

  Future<VoidCallback> deleteLoanWithUndo(String id) async {
    final l = _loans.firstWhere((x) => x.id == id);
    final payments = loanPaymentsFor(id);
    await deleteLoan(id);
    return () async {
      await _serializeMutation(() async {
        await _repo.insertLoan(l);
        if (l.transferAccountId != null) {
          await _applyAccountBalanceDelta(l.transferAccountId!, l.principal);
        }
        for (final p in payments) {
          await _repo.insertLoanPayment(p);
          if (p.accountId != null) {
            await _applyAccountBalanceDelta(p.accountId!, -p.amount);
          }
        }
        loans = await _repo.getLoans();
        loanPayments = await _repo.getAllLoanPayments();
        await _onNetWorthChanged();
        if (l.reminderEnabled) await _loanNotif.scheduleReminder(l);
      });
    };
  }

  // ── Loan payment mutations ─────────────────────────────────────────────
  Future<void> payLoanInstallment(
    Loan l, {
    double? amount,
    String? accountId,
    String notes = '',
  }) async {
    await _serializeMutation(() async {
      final payAmount = amount ?? l.monthlyPayment;
      final useAccount = accountId ?? l.accountId;

      final payment = LoanPayment(
        id: newId(),
        loanId: l.id,
        date: DateTime.now(),
        amount: payAmount,
        currency: l.currency,
        accountId: useAccount,
        notes: notes,
      );
      await _repo.insertLoanPayment(payment);
      if (useAccount != null) {
        await _applyAccountBalanceDelta(useAccount, -payAmount); // expense-like debit
      }
      loanPayments = await _repo.getAllLoanPayments();

      // Auto-settle when the loan is fully paid off (loanTotalPaid already
      // includes the inserted payment).
      final totalPaid = loanTotalPaid(l);
      if (totalPaid >= l.totalPayable && !l.isSettled) {
        final settled = l.copyWith(isSettled: true);
        await _repo.updateLoan(settled);
        loans = await _repo.getLoans();
        await _loanNotif.cancelReminder(l.id);
      }
      await _onNetWorthChanged();
    });
  }

  Future<void> skipLoanInstallment(Loan l, {String notes = 'Skipped'}) async {
    await _serializeMutation(() async {
      final payment = LoanPayment(
        id: newId(),
        loanId: l.id,
        date: DateTime.now(),
        amount: 0.0,
        currency: l.currency,
        accountId: null,
        notes: notes,
      );
      await _repo.insertLoanPayment(payment);
      loanPayments = await _repo.getAllLoanPayments();
    });
  }

  Future<void> deleteLoanPayment(String id) async {
    await _serializeMutation(() async {
      final p = _loanPayments.firstWhere((x) => x.id == id);
      if (p.accountId != null) {
        await _applyAccountBalanceDelta(p.accountId!, p.amount); // reverse the debit
      }
      await _repo.deleteLoanPayment(id);
      loanPayments = await _repo.getAllLoanPayments();

      // Re-evaluate settlement if total paid fell below totalPayable.
      final loan = _loans.where((l) => l.id == p.loanId).firstOrNull;
      if (loan != null &&
          loan.isSettled &&
          loanTotalPaid(loan) < loan.totalPayable) {
        final unsettled = loan.copyWith(isSettled: false);
        await _repo.updateLoan(unsettled);
        loans = await _repo.getLoans();
        if (unsettled.reminderEnabled) {
          await _loanNotif.scheduleReminder(unsettled);
        }
      }

      await _onNetWorthChanged();
    });
  }

  Future<VoidCallback> deleteLoanPaymentWithUndo(String id) async {
    final p = _loanPayments.firstWhere((x) => x.id == id);
    await deleteLoanPayment(id);
    return () async {
      await _serializeMutation(() async {
        await _repo.insertLoanPayment(p);
        if (p.accountId != null) {
          await _applyAccountBalanceDelta(p.accountId!, -p.amount);
        }
        loanPayments = await _repo.getAllLoanPayments();

        final loan = _loans.where((l) => l.id == p.loanId).firstOrNull;
        if (loan != null &&
            !loan.isSettled &&
            loanTotalPaid(loan) >= loan.totalPayable) {
          final settled = loan.copyWith(isSettled: true);
          await _repo.updateLoan(settled);
          loans = await _repo.getLoans();
          await _loanNotif.cancelReminder(loan.id);
        }

        await _onNetWorthChanged();
      });
    };
  }

  // ── Read helpers (pure over the owned state) ───────────────────────────
  /// All payments belonging to [loanId], most recent first.
  List<LoanPayment> loanPaymentsFor(String loanId) =>
      _loanPayments.where((p) => p.loanId == loanId).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  double loanTotalPaid(Loan l) =>
      loanPaymentsFor(l.id).fold(0.0, (s, p) => s + p.amount);

  /// Generates a new UUID for a new loan payment.
  String newId() => _uuid.v4();
}
