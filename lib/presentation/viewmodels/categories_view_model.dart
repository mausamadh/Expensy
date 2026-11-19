// lib/presentation/viewmodels/categories_view_model.dart
//
// CategoriesViewModel — Phase 6 "slim the provider" slice.
//
// Owns the user's income/expense categories (including single-level
// subcategories and the hidden system categories) and every category
// mutation. It is the single source of truth for category state; AppProvider
// delegates to it (see `AppProvider.wireCategoriesVm`).
//
// Categories have no ledger side effects (they never touch balances or
// transactions), so the view model only needs the CategoryStore port —
// no transaction hooks.
//
// Reactivity: `categories` is reassigned with a fresh list instance on every
// mutation (AGENTS.md rule 6) so UI memoization caches recompute.

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'package:finwick/domain/categories/ports/category_store.dart';
import 'package:finwick/l10n/app_localizations.dart';
import 'package:finwick/models/models.dart';
import 'package:finwick/utils/service_localizations.dart';

class CategoriesViewModel extends ChangeNotifier {
  CategoriesViewModel({
    required CategoryStore store,
    required this.serializeMutation,
  }) : _store = store;

  final CategoryStore _store;

  /// Serializes mutations against the provider's zone-based mutex so
  /// concurrent category writes can't interleave with ledger writes.
  final Future<T> Function<T>(Future<T> Function() action) serializeMutation;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  List<AppCategory> _categories = [];
  final Map<String, AppCategory> _categoriesById = {};

  List<AppCategory> get categories => _categories;
  set categories(List<AppCategory> value) {
    _categories = value;
    _categoriesById
      ..clear()
      ..addAll({for (final c in value) c.id: c});
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Read helpers
  // ---------------------------------------------------------------------------

  /// The hidden system "Transfer" category (never user-selectable).
  AppCategory get transferCategory =>
      _categoriesById['sys_transfer'] ??
      AppCategory(
        id: 'sys_transfer',
        name: 'Transfer',
        type: 'transfer',
        colorValue: 0xFF4CAF50,
      );

  AppCategory? categoryById(String id) {
    if (id == 'sys_transfer') return transferCategory;
    return _categoriesById[id];
  }

  /// Categories the user can pick for a transaction (excludes system).
  List<AppCategory> get userCategories =>
      _categories.where((c) => !c.isSystem).toList();

  /// Top-level categories of [type] (excludes system + subcategories).
  List<AppCategory> rootCategoriesForType(String type) =>
      _categories
          .where((c) => !c.isSystem && c.type == type && !c.isSubcategory)
          .toList();

  /// Subcategories of [parentId] (excludes system).
  List<AppCategory> subcategoriesOf(String parentId) =>
      _categories
          .where((c) => !c.isSystem && c.parentId == parentId)
          .toList();

  /// Resolves [categoryId] to its root parent category ID (or itself if root).
  String rootCategoryIdOf(String categoryId) {
    final cat = categoryById(categoryId);
    if (cat == null) return categoryId;
    return (cat.parentId != null && cat.parentId!.isNotEmpty)
        ? cat.parentId!
        : cat.id;
  }

  /// Resolves [categoryId] to its root parent [AppCategory].
  AppCategory? rootCategoryOf(String categoryId) =>
      categoryById(rootCategoryIdOf(categoryId));

  /// Returns [categoryId] plus all of its child subcategory IDs.
  Set<String> categoryFamilyIds(String categoryId) {
    final ids = <String>{categoryId};
    for (final c in categories) {
      if (c.parentId == categoryId) ids.add(c.id);
    }
    return ids;
  }

  /// Instance convenience wrapper using active [AppLocalizations].
  String localizedCategoryName(AppCategory cat, [AppLocalizations? l10n]) =>
      localizeCategoryName(cat, l10n ?? ServiceLocalizations.current);

  /// Returns "Parent › Subcategory" for subcategories, or "Category" for roots.
  String categoryDisplayName(String categoryId,
      {String fallback = '', AppLocalizations? l10n}) {
    final loc = l10n ?? ServiceLocalizations.current;
    final cat = categoryById(categoryId);
    if (cat == null) return fallback;
    final catLabel = localizeCategoryName(cat, loc);
    if (cat.isSubcategory) {
      final parent = categoryById(cat.parentId!);
      if (parent != null) {
        return '${localizeCategoryName(parent, loc)} › $catLabel';
      }
    }
    return catLabel;
  }

  /// Localizes a seeded default category or subcategory when its name still
  /// matches the original English default; preserves custom user-renamed names.
  static String localizeCategoryName(AppCategory cat, AppLocalizations loc) {
    final lower = cat.name.trim();
    switch (cat.id) {
      case 'food_exp':
        if (lower == 'Food & Dining') return loc.cat_food_exp;
      case 'transport':
        if (lower == 'Transport') return loc.cat_transport;
      case 'shopping':
        if (lower == 'Shopping') return loc.cat_shopping;
      case 'bills':
        if (lower == 'Bills & Utilities') return loc.cat_bills;
      case 'health':
        if (lower == 'Health') return loc.cat_health;
      case 'entertainment':
        if (lower == 'Entertainment') return loc.cat_entertainment;
      case 'education':
        if (lower == 'Education') return loc.cat_education;
      case 'personal':
        if (lower == 'Personal Care') return loc.cat_personal;
      case 'salary':
        if (lower == 'Salary') return loc.cat_salary;
      case 'freelance':
        if (lower == 'Freelance') return loc.cat_freelance;
      case 'investments':
        if (lower == 'Investments') return loc.cat_investments;
      case 'gifts':
        if (lower == 'Gifts') return loc.cat_gifts;
      case 'other_inc':
        if (lower == 'Other Income') return loc.cat_other_inc;
      case 'other_exp':
        if (lower == 'Other Expense') return loc.cat_other_exp;
      case 'sys_transfer':
        if (lower == 'Transfer') return loc.cat_sys_transfer;
      case 'sys_investment':
        if (lower == 'Investment') return loc.cat_sys_investment;
      case 'sub_food_exp_groceries':
        if (lower == 'Groceries') return loc.sub_groceries;
      case 'sub_food_exp_restaurants':
        if (lower == 'Restaurants') return loc.sub_restaurants;
      case 'sub_food_exp_delivery':
        if (lower == 'Delivery') return loc.sub_delivery;
      case 'sub_food_exp_coffee_tea':
        if (lower == 'Coffee & Tea') return loc.sub_coffee_tea;
      case 'sub_transport_fuel':
        if (lower == 'Fuel') return loc.sub_fuel;
      case 'sub_transport_public_transit':
        if (lower == 'Public Transit') return loc.sub_public_transit;
      case 'sub_transport_taxi_ride':
        if (lower == 'Taxi & Ride') return loc.sub_taxi_ride;
      case 'sub_transport_maintenance':
        if (lower == 'Maintenance') return loc.sub_maintenance;
      case 'sub_transport_parking_tolls':
        if (lower == 'Parking & Tolls') return loc.sub_parking_tolls;
      case 'sub_shopping_clothing':
        if (lower == 'Clothing') return loc.sub_clothing;
      case 'sub_shopping_electronics':
        if (lower == 'Electronics') return loc.sub_electronics;
      case 'sub_shopping_home_furniture':
        if (lower == 'Home & Furniture') return loc.sub_home_furniture;
      case 'sub_shopping_gifts':
        if (lower == 'Gifts') return loc.sub_gifts;
      case 'sub_bills_electricity':
        if (lower == 'Electricity') return loc.sub_electricity;
      case 'sub_bills_internet':
        if (lower == 'Internet') return loc.sub_internet;
      case 'sub_bills_water':
        if (lower == 'Water') return loc.sub_water;
      case 'sub_bills_phone':
        if (lower == 'Phone') return loc.sub_phone;
      case 'sub_health_medicine':
        if (lower == 'Medicine') return loc.sub_medicine;
      case 'sub_health_doctor':
        if (lower == 'Doctor') return loc.sub_doctor;
      case 'sub_entertainment_movies':
        if (lower == 'Movies') return loc.sub_movies;
      case 'sub_entertainment_games':
        if (lower == 'Games') return loc.sub_games;
      case 'sub_entertainment_subscriptions':
        if (lower == 'Subscriptions') return loc.sub_subscriptions;
    }
    return cat.name;
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  Future<void> addCategory(AppCategory c) async {
    await _store.insertCategory(c);
    categories = await _store.getCategories();
  }

  Future<void> updateCategory(AppCategory c) async {
    await _store.updateCategory(c);
    categories = await _store.getCategories();
  }

  Future<void> deleteCategory(String id) async {
    await _store.deleteCategory(id);
    categories = await _store.getCategories();
  }

  /// Reorders [type] categories (optionally scoped to [parentId]) by moving
  /// the item at [oldIndex] to [newIndex], then persists the new order.
  void reorderCategories(int oldIndex, int newIndex, String type,
      {String? parentId}) {
    if (oldIndex < newIndex) newIndex -= 1;

    final scoped = categories
        .where((c) =>
            !c.isSystem &&
            c.type == type &&
            (parentId == null ? !c.isSubcategory : c.parentId == parentId))
        .toList();
    if (oldIndex < 0 ||
        oldIndex >= scoped.length ||
        newIndex < 0 ||
        newIndex >= scoped.length) {
      return;
    }

    final item = scoped[oldIndex];
    final next = List<AppCategory>.from(categories)..remove(item);

    int insertionIndex = 0;
    int currentScopedIndex = 0;
    for (int i = 0; i < next.length; i++) {
      final c = next[i];
      final inScope = !c.isSystem &&
          c.type == type &&
          (parentId == null ? !c.isSubcategory : c.parentId == parentId);
      if (inScope) {
        if (currentScopedIndex == newIndex) {
          insertionIndex = i;
          break;
        }
        currentScopedIndex++;
      }
      insertionIndex = i + 1;
    }

    next.insert(insertionIndex, item);
    for (int i = 0; i < next.length; i++) {
      next[i] = next[i].copyWith(orderIndex: i);
    }
    categories = next;
    final ids = next.map((c) => c.id).toList();
    serializeMutation(() async {
      await _store.updateCategoryOrder(ids);
    });
  }

  /// Deletes a category (promoting its subcategories to roots) and returns an
  /// undo callback that restores the category and re-parents its children.
  Future<VoidCallback> deleteCategoryWithUndo(String id) async {
    final cat = categories.firstWhere((c) => c.id == id);
    final idx = categories.indexOf(cat);
    final childSnapshots = categories
        .where((c) => c.parentId == id)
        .map((c) => c)
        .toList();
    categories = categories
        .where((c) => c.id != id)
        .map((c) => c.parentId == id ? c.copyWith(clearParentId: true) : c)
        .toList();
    await _store.deleteCategory(id);
    return () {
      final next = List<AppCategory>.from(categories);
      final restoreIdx = idx.clamp(0, next.length);
      next.insert(restoreIdx, cat);
      for (int i = 0; i < next.length; i++) {
        if (childSnapshots.any((cs) => cs.id == next[i].id)) {
          next[i] = next[i].copyWith(parentId: id);
        }
      }
      categories = next;
      serializeMutation(() async {
        await _store.insertCategory(cat);
        for (final child in childSnapshots) {
          await _store.updateCategory(child);
        }
      });
    };
  }

  /// Seeds curated default subcategories under matching default parent
  /// categories. Returns the number of newly created subcategories.
  Future<int> seedDefaultSubcategories() async {
    return await serializeMutation(() async {
      const defaults = <String, List<String>>{
        'food_exp': [
          'Groceries',
          'Restaurants',
          'Delivery',
          'Coffee & Tea'
        ],
        'transport': [
          'Fuel',
          'Public Transit',
          'Taxi & Ride',
          'Maintenance',
          'Parking & Tolls'
        ],
        'shopping': ['Clothing', 'Electronics', 'Home & Furniture', 'Gifts'],
        'bills': ['Electricity', 'Internet', 'Water', 'Phone'],
        'health': ['Medicine', 'Doctor'],
        'entertainment': ['Movies', 'Games', 'Subscriptions'],
      };

      int added = 0;
      int nextOrder = categories.length;
      for (final entry in defaults.entries) {
        final parent = categories.where((c) => c.id == entry.key).firstOrNull;
        if (parent == null) continue;
        final existingNames = categories
            .where((c) => c.parentId == parent.id)
            .map((c) => c.name.toLowerCase())
            .toSet();
        for (final subName in entry.value) {
          if (existingNames.contains(subName.toLowerCase())) continue;
          final slug =
              subName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
          final sub = AppCategory(
            id: 'sub_${parent.id}_$slug',
            name: subName,
            type: parent.type,
            colorValue: parent.colorValue,
            iconCodePoint: 0,
            orderIndex: nextOrder++,
            parentId: parent.id,
          );
          await _store.insertCategory(sub);
          added++;
        }
      }
      if (added > 0) {
        categories = await _store.getCategories();
      }
      return added;
    });
  }
}
