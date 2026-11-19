// test/helpers/loans_test_harness.dart
//
// Shared widget-test harness for the Loans view model (Phase 6).
//
// `MainShell` eagerly builds its tabs (Transactions, More) via an
// IndexedStack, and those screens read the delegated `loans` /
// `loanPayments` collections through `LoansViewModel`. Widget tests that
// mount `MainShell` (or the loan screens directly) must therefore provide a
// `LoansViewModel` in addition to `AppProvider`. This helper builds a VM
// backed by an in-memory fake repository (no DB) and wraps a child in a
// `MultiProvider` exposing both notifiers.

import 'package:finwick/domain/loans/ports/loan_repository.dart';
import 'package:finwick/models/models.dart';
import 'package:finwick/presentation/viewmodels/loans_view_model.dart';
import 'package:finwick/providers/app_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// In-memory [LoanRepository] for widget tests — no DB access.
class InMemoryLoanRepository implements LoanRepository {
  List<Loan> _loans = [];
  List<LoanPayment> _payments = [];

  @override
  Future<List<Loan>> getLoans() async => List.unmodifiable(_loans);

  @override
  Future<void> insertLoan(Loan loan) async {
    _loans = [..._loans, loan];
  }

  @override
  Future<void> updateLoan(Loan loan) async {
    _loans = [for (final l in _loans) l.id == loan.id ? loan : l];
  }

  @override
  Future<void> deleteLoan(String id) async {
    _loans = [for (final l in _loans) if (l.id != id) l];
    _payments = [for (final p in _payments) if (p.loanId != id) p];
  }

  @override
  Future<List<LoanPayment>> getAllLoanPayments() async =>
      List.unmodifiable(_payments);

  @override
  Future<void> insertLoanPayment(LoanPayment payment) async {
    _payments = [payment, ..._payments];
  }

  @override
  Future<void> deleteLoanPayment(String id) async {
    _payments = [for (final p in _payments) if (p.id != id) p];
  }
}

/// Builds a [LoansViewModel] backed by an in-memory fake repository.
///
/// The cross-cutting hooks are no-ops in tests (no DB, no net-worth
/// snapshots, no notifications), so loan mutations run against the
/// in-memory repository only.
LoansViewModel buildLoansViewModel() => LoansViewModel(
      repository: InMemoryLoanRepository(),
      applyAccountBalanceDelta: (accountId, delta) async {},
      onNetWorthChanged: () async {},
      serializeMutation: <T>(Future<T> Function() action) => action(),
    );

/// Wraps [child] in a `MultiProvider` exposing [app] and a fresh
/// [LoansViewModel], so screens that watch the loans view model (e.g. the
/// Transactions/More tabs inside `MainShell`, or the loan screens directly)
/// resolve it in tests.
///
/// The view model is wired into [app] first, so data assigned through the
/// provider's delegating setters (`app.loans = ...`) lands in the view
/// model and its listeners fire.
Widget wrapWithLoans(AppProvider app, Widget child) {
  final vm = buildLoansViewModel();
  app.wireLoansVm(vm);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppProvider>.value(value: app),
      ChangeNotifierProvider<LoansViewModel>.value(value: vm),
    ],
    child: child,
  );
}
