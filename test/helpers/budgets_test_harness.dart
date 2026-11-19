// test/helpers/budgets_test_harness.dart
//
// Shared widget-test harness for the Budgets view model (Phase 6).
//
// Many screens read the delegated budget getters (`app.budgets`,
// `app.budgetForCategory`, `app.budgetSpent`, …) through `BudgetsViewModel`.
// Widget tests that mount those screens must therefore provide a
// `BudgetsViewModel` in addition to `AppProvider`. This helper builds a VM
// backed by an in-memory fake store (no DB) and wraps a child in a
// `MultiProvider` exposing both notifiers.
//
// The budget read math needs the provider's ledger state (transactions,
// categories, accounts, exchange rates, settings). The hooks below read
// straight off the [AppProvider] so the VM's math stays consistent with the
// provider's own state in tests.

import 'package:finwick/domain/budgeting/ports/budget_store.dart';
import 'package:finwick/models/models.dart';
import 'package:finwick/presentation/viewmodels/budgets_view_model.dart';
import 'package:finwick/providers/app_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// In-memory [BudgetStore] for widget tests — no DB access.
class InMemoryBudgetStore implements BudgetStore {
  List<Budget> _budgets = [];

  @override
  Future<List<Budget>> getBudgets() async => List.unmodifiable(_budgets);

  @override
  Future<void> insertBudget(Budget b) async {
    _budgets = [..._budgets, b];
  }

  @override
  Future<void> updateBudget(Budget b) async {
    _budgets = [for (final x in _budgets) x.id == b.id ? b : x];
  }

  @override
  Future<void> deleteBudget(String id) async {
    _budgets = [for (final x in _budgets) if (x.id != id) x];
  }
}

/// Builds a [BudgetsViewModel] backed by an in-memory fake store, with the
/// read-math hooks wired to [app] so the VM's budget math sees the same
/// ledger state the provider exposes.
BudgetsViewModel buildBudgetsViewModel(AppProvider app) => BudgetsViewModel(
      store: InMemoryBudgetStore(),
      transactions: () => app.transactions,
      categories: () => app.categories,
      accountById: app.accountById,
      settingsCurrency: () => app.settings.currency,
      exchangeRates: () => app.exchangeRates,
      weekStart: () => app.settings.weekStart,
      getSplits: app.getSplits,
      updateHomeWidgets: app.updateHomeWidgets,
      serializeMutation: <T>(Future<T> Function() action) => action(),
    );

/// Wraps [child] in a `MultiProvider` exposing [app] and a fresh
/// [BudgetsViewModel], so screens that watch the budgets view model resolve
/// it in tests.
///
/// The view model is wired into [app] first, so data assigned through the
/// provider's delegating setters (`app.budgets = ...`) lands in the view
/// model and its listeners fire.
Widget wrapWithBudgets(AppProvider app, Widget child) {
  final vm = buildBudgetsViewModel(app);
  app.wireBudgetsVm(vm);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppProvider>.value(value: app),
      ChangeNotifierProvider<BudgetsViewModel>.value(value: vm),
    ],
    child: child,
  );
}
