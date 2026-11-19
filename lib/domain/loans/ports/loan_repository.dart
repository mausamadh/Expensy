// lib/domain/loans/ports/loan_repository.dart
//
// Domain port for the Loans bounded context (Phase 6) — personal loans the
// user has taken (with an amortization schedule) and the individual
// installment payments that form each loan's ledger history.
//
// Pure Dart: imports only the shared models. The concrete Drift adapter
// lives in `adapters/` and is injected by the composition root.
//
// Note: the ledger-coupled side effects (reversing/applying principal
// transfers and installment debits on an account, net-worth snapshots,
// reminder scheduling) are NOT part of this port — they are handled by the
// view model through injected hooks.

import 'package:finwick/models/models.dart';

abstract interface class LoanRepository {
  // ── Loans ─────────────────────────────────────────────────────────────
  Future<List<Loan>> getLoans();
  Future<void> insertLoan(Loan loan);
  Future<void> updateLoan(Loan loan);
  Future<void> deleteLoan(String id);

  // ── Loan payments (installment ledger) ────────────────────────────────
  Future<List<LoanPayment>> getAllLoanPayments();
  Future<void> insertLoanPayment(LoanPayment payment);
  Future<void> deleteLoanPayment(String id);
}
