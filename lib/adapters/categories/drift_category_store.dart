// lib/adapters/categories/drift_category_store.dart
//
// Drift-backed persistence adapter for the Categories bounded context
// (Phase 6).
//
// Thin wrapper over the existing AppDatabase category methods (which
// delegate to [AppDatabase.instance]) — no SQL changes.

import 'package:finwick/database/app_database.dart';
import 'package:finwick/domain/categories/ports/category_store.dart';
import 'package:finwick/models/models.dart';

class DriftCategoryStore implements CategoryStore {
  const DriftCategoryStore();

  @override
  Future<List<AppCategory>> getCategories() =>
      AppDatabase.instance.getCategories();

  @override
  Future<void> insertCategory(AppCategory category) =>
      AppDatabase.instance.insertCategory(category);

  @override
  Future<void> updateCategory(AppCategory category) =>
      AppDatabase.instance.updateCategory(category);

  @override
  Future<void> deleteCategory(String id) =>
      AppDatabase.instance.deleteCategory(id);

  @override
  Future<void> updateCategoryOrder(List<String> orderedIds) =>
      AppDatabase.instance.updateCategoryOrder(orderedIds);
}
