// lib/domain/budgeting/budget_service.dart
//
// Pure domain service for the Budgeting bounded context (hexagonal
// architecture, HEXAGONAL_MIGRATION_PLAN.md §5 Phase 3).
//
// Encapsulates the budget period math, spend / rollover / allowance
// computation, and Safe-to-Spend pacing that were previously inlined in
// `AppProvider`. The service is dependency-free and deterministic: it operates
// on the in-memory ledger state handed to it via [BudgetContext].
//
// No Flutter, Drift, or plugin imports (enforced by ci_guard).

import 'package:finwick/models/models.dart';
import 'package:intl/intl.dart';

import '../ledger/balance_delta.dart' show BalanceDeltaService;
import 'aggregations.dart' show FinancialAggregations;

/// Resolves an account by id. Returns null when the account does not exist.
typedef AccountLookup = Account? Function(String id);

/// Resolves the split lines for a transaction (empty when not split).
typedef SplitsResolver = List<TransactionSplit> Function(String txId);

/// The in-memory budgeting state handed to [BudgetService]. Mirrors the
/// provider's `transactions`, `categories`, `budgets`, `accounts`, exchange
/// rates, and settings.
class BudgetContext {
  final List<AppTransaction> transactions;
  final List<AppCategory> categories;
  final List<Budget> budgets;
  final AccountLookup accountById;
  final String settingsCurrency;
  final Map<String, double> exchangeRates;
  final String weekStart;
  final SplitsResolver getSplits;

  const BudgetContext({
    required this.transactions,
    required this.categories,
    required this.budgets,
    required this.accountById,
    required this.settingsCurrency,
    required this.exchangeRates,
    required this.weekStart,
    required this.getSplits,
  });
}

/// Pure rules for budget period math, spend / rollover / allowance, and
/// Safe-to-Spend pacing.
class BudgetService {
  const BudgetService();

  final BalanceDeltaService _delta = const BalanceDeltaService();

  // ── Category helpers ──────────────────────────────────────────────────

  AppCategory? categoryById(BudgetContext ctx, String id) {
    for (final c in ctx.categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Returns [categoryId] plus all of its child subcategory IDs.
  Set<String> categoryFamilyIds(BudgetContext ctx, String categoryId) {
    final ids = <String>{categoryId};
    for (final c in ctx.categories) {
      if (c.parentId == categoryId) ids.add(c.id);
    }
    return ids;
  }

  // ── Budget lookup / rollup ────────────────────────────────────────────

  Budget? budgetForCategory(BudgetContext ctx, String categoryId) {
    for (final b in ctx.budgets) {
      if (b.categoryId == categoryId) return b;
    }
    return null;
  }

  /// Returns budgets excluding child subcategory budgets whose parent category
  /// also has an active budget of the same period, preventing double-counting
  /// in aggregate budget totals and pacing.
  List<Budget> nonOverlappingBudgets(BudgetContext ctx) {
    final activeKeys = {
      for (final b in ctx.budgets) '${b.categoryId}:${b.period}',
    };
    return ctx.budgets.where((b) {
      final cat = categoryById(ctx, b.categoryId);
      if (cat == null || !cat.isSubcategory) return true;
      return !activeKeys.contains('${cat.parentId}:${b.period}');
    }).toList();
  }

  // ── Period math ───────────────────────────────────────────────────────

  DateTime getCurrentPeriodStart(
      BudgetContext ctx, Budget budget, [DateTime? referenceDate]) {
    final now = referenceDate ?? DateTime.now();
    if (budget.period == 'weekly') {
      final dow = now.weekday; // 1=Mon, 7=Sun
      final offset = ctx.weekStart == 'monday' ? (dow - 1) : (dow % 7);
      return DateTime(now.year, now.month, now.day - offset);
    } else {
      return DateTime(now.year, now.month, 1);
    }
  }

  DateTime getPreviousPeriodStart(
      BudgetContext ctx, Budget budget, [DateTime? referenceDate]) {
    final now = referenceDate ?? DateTime.now();
    if (budget.period == 'weekly') {
      final currentStart = getCurrentPeriodStart(ctx, budget, now);
      return currentStart.subtract(const Duration(days: 7));
    } else {
      return DateTime(now.year, now.month - 1, 1);
    }
  }

  // ── Spend / rollover / allowance ──────────────────────────────────────

  /// Converts [amount] from [fromCurrency] to the settings currency, falling
  /// back to the unconverted amount when no usable rate exists.
  double convertToMain(
    BudgetContext ctx,
    double amount,
    String fromCurrency,
  ) {
    if (fromCurrency == ctx.settingsCurrency || ctx.exchangeRates.isEmpty) {
      return amount;
    }
    return _delta.convert(amount, fromCurrency, ctx.settingsCurrency,
            ctx.exchangeRates) ??
        amount;
  }

  /// Calculates spending for a budget's category (including any child
  /// subcategories) within the half-open date interval [start, end).
  double budgetSpentInPeriod(
    BudgetContext ctx,
    Budget budget,
    DateTime start,
    DateTime end,
  ) {
    final familyIds = categoryFamilyIds(ctx, budget.categoryId);
    return ctx.transactions
        .where((t) =>
            t.type == 'expense' &&
            !FinancialAggregations.isExcludedFromTotals(t) &&
            !t.date.isBefore(start) &&
            t.date.isBefore(end))
        .fold(0.0, (sum, t) {
      final acct = ctx.accountById(t.accountId);
      final txCur = t.currency.isNotEmpty
          ? t.currency
          : (acct?.currency ?? ctx.settingsCurrency);
      final txSplits = ctx.getSplits(t.id);
      if (txSplits.isNotEmpty) {
        final splitSplits =
            txSplits.where((s) => familyIds.contains(s.categoryId));
        if (splitSplits.isEmpty) return sum;
        final splitSum = splitSplits.fold(0.0, (s, item) => s + item.amount);
        return sum + convertToMain(ctx, splitSum, txCur);
      } else {
        if (!familyIds.contains(t.categoryId)) return sum;
        return sum + convertToMain(ctx, t.amount, txCur);
      }
    });
  }

  /// Sum of all expenses for [budget]'s category in the current period,
  /// converted to the main currency.
  double budgetSpent(BudgetContext ctx, Budget budget, [DateTime? referenceDate]) {
    final now = referenceDate ?? DateTime.now();
    final periodStart = getCurrentPeriodStart(ctx, budget, now);
    final periodEnd = budget.period == 'weekly'
        ? periodStart.add(const Duration(days: 7))
        : DateTime(now.year, now.month + 1, 1);
    return budgetSpentInPeriod(ctx, budget, periodStart, periodEnd);
  }

  /// Computes the rollover surplus (positive) or overspending deficit (negative)
  /// from the previous period if [budget.allowRollover] is true.
  /// If rollover is disabled, returns 0.0.
  double budgetRollover(BudgetContext ctx, Budget budget, [DateTime? referenceDate]) {
    if (!budget.allowRollover) return 0.0;
    final now = referenceDate ?? DateTime.now();
    final prevStart = getPreviousPeriodStart(ctx, budget, now);
    final currentStart = getCurrentPeriodStart(ctx, budget, now);

    final prevSpent = budgetSpentInPeriod(ctx, budget, prevStart, currentStart);

    // Brand-new budgets created in the current period must not inherit a
    // synthetic surplus or deficit from pre-budget transactions (C6).
    if (!budget.createdAt.isBefore(currentStart)) {
      return 0.0;
    }

    return budget.amount - prevSpent;
  }

  /// Effective budget allowance for the current period:
  /// Base Budget + Rollover (if enabled). Clamped to at least 0.
  double budgetEffectiveAllowance(
      BudgetContext ctx, Budget budget, [DateTime? referenceDate]) {
    if (!budget.allowRollover) return budget.amount;
    final rollover = budgetRollover(ctx, budget, referenceDate);
    final effective = budget.amount + rollover;
    return effective < 0 ? 0.0 : effective;
  }

  /// Progress against the effective budget allowance (0.0 to 1.0).
  double budgetProgress(BudgetContext ctx, Budget b) {
    final allowance = budgetEffectiveAllowance(ctx, b);
    if (allowance <= 0) {
      return budgetSpent(ctx, b) > 0 ? 1.0 : 0.0;
    }
    return (budgetSpent(ctx, b) / allowance).clamp(0.0, 1.0);
  }

  /// True if current spending exceeds the effective budget allowance.
  bool budgetExceeded(BudgetContext ctx, Budget b) =>
      budgetSpent(ctx, b) > budgetEffectiveAllowance(ctx, b);

  /// Label of the previous period (e.g. "Aug", "Last Week") for rollover
  /// subheaders.
  String previousPeriodName(BudgetContext ctx, Budget budget,
      [String? lastWeekLabel, DateTime? referenceDate]) {
    final now = referenceDate ?? DateTime.now();
    if (budget.period == 'weekly') {
      return lastWeekLabel ?? 'Last Week';
    } else {
      final prevMonthDate = DateTime(now.year, now.month - 1, 1);
      return DateFormat.MMM().format(prevMonthDate);
    }
  }

  // ── Pacing ────────────────────────────────────────────────────────────

  /// Computes the daily Safe-to-Spend pacing analysis for [budget].
  BudgetPacingInfo budgetPacing(
      BudgetContext ctx, Budget budget, [DateTime? referenceDate]) {
    final now = referenceDate ?? DateTime.now();
    final periodStart = getCurrentPeriodStart(ctx, budget, now);
    final int totalDays;
    final int elapsedDays;

    if (budget.period == 'weekly') {
      totalDays = 7;
      final diff = now.difference(periodStart).inDays + 1;
      elapsedDays = diff.clamp(1, 7);
    } else {
      totalDays = DateTime(now.year, now.month + 1, 0).day;
      elapsedDays = now.day.clamp(1, totalDays);
    }

    final daysRemaining = (totalDays - elapsedDays + 1).clamp(1, totalDays);
    final allowance = budgetEffectiveAllowance(ctx, budget, now);
    final spent = budgetSpent(ctx, budget, now);
    final remaining = allowance - spent;
    final safeDaily = (allowance > 0 && remaining > 0)
        ? remaining / daysRemaining
        : 0.0;

    final double pacingRatio;
    if (allowance <= 0) {
      pacingRatio = spent > 0 ? 999.0 : 1.0;
    } else {
      final spentFrac = spent / allowance;
      final timeFrac = elapsedDays / totalDays;
      pacingRatio = timeFrac > 0 ? (spentFrac / timeFrac) : 1.0;
    }

    final BudgetPacingStatus status;
    if (spent > allowance) {
      status = BudgetPacingStatus.exceeded;
    } else if (pacingRatio > 1.25) {
      status = BudgetPacingStatus.overPaced;
    } else if (pacingRatio > 1.0) {
      status = BudgetPacingStatus.caution;
    } else {
      status = BudgetPacingStatus.onTrack;
    }

    return BudgetPacingInfo(
      safeDailyAllowance: safeDaily,
      pacingRatio: pacingRatio,
      daysRemaining: daysRemaining,
      totalDaysInPeriod: totalDays,
      elapsedDays: elapsedDays,
      spent: spent,
      allowance: allowance,
      remainingAmount: remaining < 0 ? 0.0 : remaining,
      status: status,
    );
  }

  /// Aggregated Safe-to-Spend daily pacing analysis across all monthly category
  /// budgets. Returns null if no monthly budgets are configured.
  BudgetPacingInfo? overallMonthlyBudgetPacing(
      BudgetContext ctx, [DateTime? referenceDate]) {
    final monthlyBudgets =
        nonOverlappingBudgets(ctx).where((b) => b.period == 'monthly').toList();
    if (monthlyBudgets.isEmpty) return null;

    final now = referenceDate ?? DateTime.now();
    final totalDays = DateTime(now.year, now.month + 1, 0).day;
    final elapsedDays = now.day.clamp(1, totalDays);
    final daysRemaining = (totalDays - elapsedDays + 1).clamp(1, totalDays);

    double totalAllowance = 0.0;
    double totalSpent = 0.0;

    for (final b in monthlyBudgets) {
      totalAllowance += budgetEffectiveAllowance(ctx, b, now);
      totalSpent += budgetSpent(ctx, b, now);
    }

    final remaining = totalAllowance - totalSpent;
    final safeDaily = (totalAllowance > 0 && remaining > 0)
        ? remaining / daysRemaining
        : 0.0;

    final double pacingRatio;
    if (totalAllowance <= 0) {
      pacingRatio = totalSpent > 0 ? 999.0 : 1.0;
    } else {
      final spentFrac = totalSpent / totalAllowance;
      final timeFrac = elapsedDays / totalDays;
      pacingRatio = timeFrac > 0 ? (spentFrac / timeFrac) : 1.0;
    }

    final BudgetPacingStatus status;
    if (totalSpent > totalAllowance) {
      status = BudgetPacingStatus.exceeded;
    } else if (pacingRatio > 1.25) {
      status = BudgetPacingStatus.overPaced;
    } else if (pacingRatio > 1.0) {
      status = BudgetPacingStatus.caution;
    } else {
      status = BudgetPacingStatus.onTrack;
    }

    return BudgetPacingInfo(
      safeDailyAllowance: safeDaily,
      pacingRatio: pacingRatio,
      daysRemaining: daysRemaining,
      totalDaysInPeriod: totalDays,
      elapsedDays: elapsedDays,
      spent: totalSpent,
      allowance: totalAllowance,
      remainingAmount: remaining < 0 ? 0.0 : remaining,
      status: status,
    );
  }
}
