// lib/adapters/loans/drift_loan_repository.dart
//
// Drift-backed persistence adapter for the Loans bounded context (Phase 6).
//
// Thin wrapper over the existing AppDatabase loan / loan-payment methods
// (which delegate to [AppDatabase.instance]) — no SQL changes.

import 'package:finwick/database/app_database.dart';
import 'package:finwick/domain/loans/ports/loan_repository.dart';
import 'package:finwick/models/models.dart';

class DriftLoanRepository implements LoanRepository {
  const DriftLoanRepository();

  // ── Loans ─────────────────────────────────────────────────────────────
  @override
  Future<List<Loan>> getLoans() => AppDatabase.instance.getLoans();

  @override
  Future<void> insertLoan(Loan loan) => AppDatabase.instance.insertLoan(loan);

  @override
  Future<void> updateLoan(Loan loan) => AppDatabase.instance.updateLoan(loan);

  @override
  Future<void> deleteLoan(String id) => AppDatabase.instance.deleteLoan(id);

  // ── Loan payments ─────────────────────────────────────────────────────
  @override
  Future<List<LoanPayment>> getAllLoanPayments() =>
      AppDatabase.instance.getAllLoanPayments();

  @override
  Future<void> insertLoanPayment(LoanPayment payment) =>
      AppDatabase.instance.insertLoanPayment(payment);

  @override
  Future<void> deleteLoanPayment(String id) =>
      AppDatabase.instance.deleteLoanPayment(id);
}
