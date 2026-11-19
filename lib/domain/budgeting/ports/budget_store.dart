// lib/domain/budgeting/ports/budget_store.dart
//
// Read+write port for the Budgeting bounded context (Phase 6).
//
// The view model needs to reload the budget list after every mutation, so
// this store combines the read side (`getBudgets`) with the write side
// (mirroring the `CategoryStore` precedent). The existing write-only
// `BudgetWriteRepository` port stays for the application-layer use cases.
//
// Pure Dart: imports only the shared models. The concrete Drift adapter
// lives in `adapters/` and is injected by the composition root.

import 'package:finwick/models/models.dart';

abstract interface class BudgetStore {
  Future<List<Budget>> getBudgets();
  Future<void> insertBudget(Budget b);
  Future<void> updateBudget(Budget b);
  Future<void> deleteBudget(String id);
}
