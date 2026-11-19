// lib/presentation/viewmodels/budgets_view_model.dart
//
// Presentation-layer view model for the Budgeting bounded context (Phase 6,
// "Slim the provider") — the user's per-category budgets and the budget
// period / spend / rollover / pacing math over them.
//
// Owns the `budgets` state slice and delegates every mutation to the
// [BudgetStore] port. Read math is delegated to the pure domain
// [BudgetService], which operates on a [BudgetContext] assembled from the
// injected cross-cutting hooks below.
//
// Cross-cutting couplings are injected as functions rather than a provider
// reference, keeping this file free of any `providers/` import:
//   * [transactions] / [categories] — the ledger state the budget math reads.
//   * [accountById] — resolves an account id to an account (currency lookup).
//   * [settingsCurrency] / [weekStart] — main currency and week-start day.
//   * [exchangeRates] — currency conversion table.
//   * [getSplits] — resolves a transaction's split lines.
//   * [updateHomeWidgets] — debounced home-widget refresh after mutations.
//   * [serializeMutation] — the provider's zone-based mutation mutex, so
//     budget writes serialize with the provider's own writes.
//
// Layering: this file lives in `presentation/` and imports only `domain/`
// and `models/` — never `adapters/` or `database/`. The store is injected
// through the constructor by the composition root.

import 'package:flutter/foundation.dart';

import 'package:finwick/domain/budgeting/budget_service.dart';
import 'package:finwick/domain/budgeting/ports/budget_store.dart';
import 'package:finwick/models/models.dart';

class BudgetsViewModel extends ChangeNotifier {
  BudgetsViewModel({
    required BudgetStore store,
    required List<AppTransaction> Function() transactions,
    required List<AppCategory> Function() categories,
    required AccountLookup accountById,
    required String Function() settingsCurrency,
    required Map<String, double> Function() exchangeRates,
    required String Function() weekStart,
    required SplitsResolver getSplits,
    required void Function() updateHomeWidgets,
    required Future<T> Function<T>(Future<T> Function()) serializeMutation,
  })  : _store = store,
        _transactions = transactions,
        _categories = categories,
        _accountById = accountById,
        _settingsCurrency = settingsCurrency,
        _exchangeRates = exchangeRates,
        _weekStart = weekStart,
        _getSplits = getSplits,
        _updateHomeWidgets = updateHomeWidgets,
        _serializeMutation = serializeMutation;

  final BudgetStore _store;
  final List<AppTransaction> Function() _transactions;
  final List<AppCategory> Function() _categories;
  final AccountLookup _accountById;
  final String Function() _settingsCurrency;
  final Map<String, double> Function() _exchangeRates;
  final String Function() _weekStart;
  final SplitsResolver _getSplits;
  final void Function() _updateHomeWidgets;
  final Future<T> Function<T>(Future<T> Function()) _serializeMutation;

  final BudgetService _budgetService = const BudgetService();

  // ── State ──────────────────────────────────────────────────────────────
  List<Budget> _budgets = [];

  /// All budgets (creation order per the DB query).
  List<Budget> get budgets => _budgets;

  /// Replaces the budget list (fresh-list reactivity rule: reassign, never
  /// mutate in place) and notifies listeners.
  set budgets(List<Budget> next) {
    _budgets = next;
    notifyListeners();
  }

  /// Loads the budget list from the store (used at startup and after
  /// mutations).
  Future<void> load() async {
    _budgets = await _store.getBudgets();
    notifyListeners();
  }

  // ── Mutations ──────────────────────────────────────────────────────────
  Future<void> addBudget(Budget b) async {
    await _serializeMutation(() async {
      await _store.insertBudget(b);
      _budgets = await _store.getBudgets();
      notifyListeners();
    });
    _updateHomeWidgets();
  }

  Future<void> updateBudget(Budget b) async {
    await _serializeMutation(() async {
      await _store.updateBudget(b);
      _budgets = await _store.getBudgets();
      notifyListeners();
    });
    _updateHomeWidgets();
  }

  Future<void> deleteBudget(String id) async {
    await _serializeMutation(() async {
      await _store.deleteBudget(id);
      _budgets = await _store.getBudgets();
      notifyListeners();
    });
    _updateHomeWidgets();
  }

  /// Deletes a budget and returns an undo callback that re-inserts it.
  Future<VoidCallback> deleteBudgetWithUndo(String id) async {
    final b = _budgets.firstWhere((b) => b.id == id);
    await deleteBudget(id);
    return () async {
      await addBudget(b);
    };
  }

  // ── Read math (delegated to the pure BudgetService) ────────────────────
  /// The in-memory budgeting state handed to the pure [BudgetService].
  BudgetContext get _context => BudgetContext(
        transactions: _transactions(),
        categories: _categories(),
        budgets: _budgets,
        accountById: _accountById,
        settingsCurrency: _settingsCurrency(),
        exchangeRates: _exchangeRates(),
        weekStart: _weekStart(),
        getSplits: _getSplits,
      );

  Budget? budgetForCategory(String categoryId) =>
      _budgetService.budgetForCategory(_context, categoryId);

  /// Returns budgets excluding child subcategory budgets whose parent category
  /// also has an active budget of the same period, preventing double-counting
  /// in aggregate budget totals and pacing.
  List<Budget> get nonOverlappingBudgets =>
      _budgetService.nonOverlappingBudgets(_context);

  DateTime getCurrentPeriodStart(Budget budget, [DateTime? referenceDate]) =>
      _budgetService.getCurrentPeriodStart(_context, budget, referenceDate);

  DateTime getPreviousPeriodStart(Budget budget, [DateTime? referenceDate]) =>
      _budgetService.getPreviousPeriodStart(_context, budget, referenceDate);

  /// Calculates spending for a budget's category (including any child
  /// subcategories) within the half-open date interval [start, end).
  double budgetSpentInPeriod(Budget budget, DateTime start, DateTime end) =>
      _budgetService.budgetSpentInPeriod(_context, budget, start, end);

  /// Sum of all expenses for [budget]'s category in the current period,
  /// converted to the main currency.
  double budgetSpent(Budget budget, [DateTime? referenceDate]) =>
      _budgetService.budgetSpent(_context, budget, referenceDate);

  /// Computes the rollover surplus (positive) or overspending deficit (negative)
  /// from the previous period if [budget.allowRollover] is true.
  /// If rollover is disabled, returns 0.0.
  double budgetRollover(Budget budget, [DateTime? referenceDate]) =>
      _budgetService.budgetRollover(_context, budget, referenceDate);

  /// Effective budget allowance for the current period:
  /// Base Budget + Rollover (if enabled). Clamped to at least 0.
  double budgetEffectiveAllowance(Budget budget, [DateTime? referenceDate]) =>
      _budgetService.budgetEffectiveAllowance(_context, budget, referenceDate);

  /// Progress against the effective budget allowance (0.0 to 1.0).
  double budgetProgress(Budget b) => _budgetService.budgetProgress(_context, b);

  /// True if current spending exceeds the effective budget allowance.
  bool budgetExceeded(Budget b) => _budgetService.budgetExceeded(_context, b);

  /// Label of the previous period (e.g. "Aug", "Last Week") for rollover subheaders.
  String previousPeriodName(Budget budget,
          [String? lastWeekLabel, DateTime? referenceDate]) =>
      _budgetService.previousPeriodName(
          _context, budget, lastWeekLabel, referenceDate);

  /// Computes the daily Safe-to-Spend pacing analysis for [budget].
  BudgetPacingInfo budgetPacing(Budget budget, [DateTime? referenceDate]) =>
      _budgetService.budgetPacing(_context, budget, referenceDate);

  /// Aggregated Safe-to-Spend daily pacing analysis across all monthly category budgets.
  /// Returns null if no monthly budgets are configured.
  BudgetPacingInfo? overallMonthlyBudgetPacing([DateTime? referenceDate]) =>
      _budgetService.overallMonthlyBudgetPacing(_context, referenceDate);
}
