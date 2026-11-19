// test/helpers/categories_test_harness.dart
//
// Shared widget-test harness for the Categories view model (Phase 6).
//
// Many screens read the delegated category getters (`app.categories`,
// `app.userCategories`, `app.categoryById`, …) through `CategoriesViewModel`.
// Widget tests that mount those screens must therefore provide a
// `CategoriesViewModel` in addition to `AppProvider`. This helper builds a VM
// backed by an in-memory fake store (no DB) and wraps a child in a
// `MultiProvider` exposing both notifiers.

import 'package:finwick/domain/categories/ports/category_store.dart';
import 'package:finwick/models/models.dart';
import 'package:finwick/presentation/viewmodels/categories_view_model.dart';
import 'package:finwick/providers/app_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// In-memory [CategoryStore] for widget tests — no DB access.
class InMemoryCategoryStore implements CategoryStore {
  List<AppCategory> _categories = [];

  @override
  Future<List<AppCategory>> getCategories() async =>
      List.unmodifiable(_categories);

  @override
  Future<void> insertCategory(AppCategory category) async {
    _categories = [..._categories, category];
  }

  @override
  Future<void> updateCategory(AppCategory category) async {
    _categories = [for (final c in _categories) c.id == category.id ? category : c];
  }

  @override
  Future<void> deleteCategory(String id) async {
    _categories = [for (final c in _categories) if (c.id != id) c];
  }

  @override
  Future<void> updateCategoryOrder(List<String> orderedIds) async {}
}

/// Builds a [CategoriesViewModel] backed by an in-memory fake store.
///
/// Categories have no ledger side effects, so the only hook is
/// [serializeMutation], which is a pass-through in tests (no mutex).
CategoriesViewModel buildCategoriesViewModel() => CategoriesViewModel(
      store: InMemoryCategoryStore(),
      serializeMutation: <T>(Future<T> Function() action) => action(),
    );

/// Wraps [child] in a `MultiProvider` exposing [app] and a fresh
/// [CategoriesViewModel], so screens that watch the categories view model
/// resolve it in tests.
///
/// The view model is wired into [app] first, so data assigned through the
/// provider's delegating setters (`app.categories = ...`) lands in the view
/// model and its listeners fire.
Widget wrapWithCategories(AppProvider app, Widget child) {
  final vm = buildCategoriesViewModel();
  app.wireCategoriesVm(vm);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppProvider>.value(value: app),
      ChangeNotifierProvider<CategoriesViewModel>.value(value: vm),
    ],
    child: child,
  );
}
