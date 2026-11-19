// lib/application/budgeting/budget_write_use_cases.dart
//
// Application-layer write use cases for the Budgeting bounded context
// (hexagonal architecture, HEXAGONAL_MIGRATION_PLAN.md §5 Phase 3).
//
// Each use case performs the DB write through the [BudgetWriteRepository]
// port. Budgets carry no balance side effects, so the use cases are thin
// orchestration over the port. The provider keeps the in-memory `budgets`
// sync and side effects (notifications, widgets) under its own mutex.
//
// No Flutter, Drift, or plugin imports (enforced by ci_guard).

import 'package:finwick/domain/budgeting/ports/budget_write_port.dart';
import 'package:finwick/models/models.dart';

/// Adds a new budget.
class AddBudget {
  AddBudget({required BudgetWriteRepository budgets}) : _budgets = budgets;

  final BudgetWriteRepository _budgets;

  Future<void> call(Budget b) async {
    await _budgets.insertBudget(b);
  }
}

/// Updates an existing budget.
class UpdateBudget {
  UpdateBudget({required BudgetWriteRepository budgets}) : _budgets = budgets;

  final BudgetWriteRepository _budgets;

  Future<void> call(Budget b) async {
    await _budgets.updateBudget(b);
  }
}

/// Deletes the budget [id].
class DeleteBudget {
  DeleteBudget({required BudgetWriteRepository budgets}) : _budgets = budgets;

  final BudgetWriteRepository _budgets;

  Future<void> call(String id) async {
    await _budgets.deleteBudget(id);
  }
}
