// lib/domain/budgeting/ports/budget_write_port.dart
//
// Write-side port for the Budgeting bounded context (hexagonal architecture,
// HEXAGONAL_MIGRATION_PLAN.md §5 Phase 3).
//
// Domain-owned interface for budget persistence. The application layer
// programs against this; the Drift adapter (lib/adapters/budgeting/) provides
// the concrete implementation over the existing AppDatabase. No Flutter,
// Drift, or plugin imports here (enforced by ci_guard).

import 'package:finwick/models/models.dart';

/// Write access to budgets.
abstract interface class BudgetWriteRepository {
  /// Inserts a new budget.
  Future<void> insertBudget(Budget b);

  /// Updates an existing budget.
  Future<void> updateBudget(Budget b);

  /// Deletes the budget [id].
  Future<void> deleteBudget(String id);
}
