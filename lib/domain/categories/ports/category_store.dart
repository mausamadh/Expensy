// lib/domain/categories/ports/category_store.dart
//
// Domain port for the Categories bounded context (Phase 6) — the user's
// income/expense categories, including single-level subcategories
// (`parent_id`) and the hidden system categories (`sys_transfer`,
// `sys_investment`).
//
// Pure Dart: imports only the shared models. The concrete Drift adapter
// lives in `adapters/` and is injected by the composition root.
//
// Named `CategoryStore` (not `CategoryRepository`) to avoid colliding with
// the ledger domain's read-only `CategoryRepository` port.
//
// Note: category mutations have no ledger side effects (they never touch
// account balances or transactions), so this port is the whole persistence
// surface — no extra hooks are needed by the view model.

import 'package:finwick/models/models.dart';

abstract interface class CategoryStore {
  Future<List<AppCategory>> getCategories();
  Future<void> insertCategory(AppCategory category);
  Future<void> updateCategory(AppCategory category);
  Future<void> deleteCategory(String id);

  /// Persists a new ordering: [orderedIds] is the full category id list in
  /// display order; the adapter writes `order_index = position` for each.
  Future<void> updateCategoryOrder(List<String> orderedIds);
}
