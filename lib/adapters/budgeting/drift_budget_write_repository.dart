// lib/adapters/budgeting/drift_budget_write_repository.dart
//
// Drift-backed write adapter for the Budgeting bounded context (Phase 3).
//
// Thin wrapper over the existing AppDatabase methods (which delegate to
// [AppDatabase.instance]) — no SQL changes.

import 'package:finwick/database/app_database.dart';
import 'package:finwick/domain/budgeting/ports/budget_write_port.dart';
import 'package:finwick/models/models.dart';

class DriftBudgetWriteRepository implements BudgetWriteRepository {
  const DriftBudgetWriteRepository();

  @override
  Future<void> insertBudget(Budget b) => AppDatabase.instance.insertBudget(b);

  @override
  Future<void> updateBudget(Budget b) => AppDatabase.instance.updateBudget(b);

  @override
  Future<void> deleteBudget(String id) => AppDatabase.instance.deleteBudget(id);
}
