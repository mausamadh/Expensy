// lib/adapters/budgeting/drift_budget_store.dart
//
// Drift-backed read+write adapter for the Budgeting bounded context
// (Phase 6). Thin wrapper over the existing AppDatabase methods — no SQL
// changes.

import 'package:finwick/database/app_database.dart';
import 'package:finwick/domain/budgeting/ports/budget_store.dart';
import 'package:finwick/models/models.dart';

class DriftBudgetStore implements BudgetStore {
  const DriftBudgetStore();

  @override
  Future<List<Budget>> getBudgets() => AppDatabase.instance.getBudgets();

  @override
  Future<void> insertBudget(Budget b) => AppDatabase.instance.insertBudget(b);

  @override
  Future<void> updateBudget(Budget b) => AppDatabase.instance.updateBudget(b);

  @override
  Future<void> deleteBudget(String id) => AppDatabase.instance.deleteBudget(id);
}
