// test/helpers/goals_test_harness.dart
//
// Shared widget-test harness for the Goals view model (Phase 6).
//
// `MainShell` eagerly builds its tabs (Transactions, Budget, More) via an
// IndexedStack, and those screens read the delegated `wishlist` /
// `savingsGoals` / `savingsContributions` collections through
// `GoalsViewModel`. Widget tests that mount `MainShell` (or the goals
// screens directly) must therefore provide a `GoalsViewModel` in addition to
// `AppProvider`. This helper builds a VM backed by an in-memory fake
// repository (no DB) and wraps a child in a `MultiProvider` exposing both
// notifiers.

import 'package:finwick/domain/goals/ports/goals_repository.dart';
import 'package:finwick/models/models.dart';
import 'package:finwick/presentation/viewmodels/goals_view_model.dart';
import 'package:finwick/providers/app_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// In-memory [GoalsRepository] for widget tests — no DB access.
class InMemoryGoalsRepository implements GoalsRepository {
  List<WishlistItem> _wishlist = [];
  List<SavingsGoal> _goals = [];
  List<SavingsContribution> _contributions = [];

  @override
  Future<List<WishlistItem>> getAllWishlist() async =>
      List.unmodifiable(_wishlist);

  @override
  Future<void> insertWishlist(WishlistItem item) async {
    _wishlist = [item, ..._wishlist];
  }

  @override
  Future<void> updateWishlist(WishlistItem item) async {
    _wishlist = [
      for (final w in _wishlist) w.id == item.id ? item : w,
    ];
  }

  @override
  Future<void> deleteWishlist(String id) async {
    _wishlist = [for (final w in _wishlist) if (w.id != id) w];
  }

  @override
  Future<List<SavingsGoal>> getAllGoals() async =>
      List.unmodifiable(_goals);

  @override
  Future<void> insertGoal(SavingsGoal goal) async {
    _goals = [..._goals, goal];
  }

  @override
  Future<void> updateGoal(SavingsGoal goal) async {
    _goals = [
      for (final g in _goals) g.id == goal.id ? goal : g,
    ];
  }

  @override
  Future<void> deleteGoal(String id) async {
    _goals = [for (final g in _goals) if (g.id != id) g];
  }

  @override
  Future<List<SavingsContribution>> getAllContributions() async =>
      List.unmodifiable(_contributions);
}

/// Builds a [GoalsViewModel] backed by an in-memory fake repository.
GoalsViewModel buildGoalsViewModel() =>
    GoalsViewModel(repository: InMemoryGoalsRepository());

/// Wraps [child] in a `MultiProvider` exposing [app] and a fresh
/// [GoalsViewModel], so screens that watch the goals view model (e.g. the
/// Budget/Transactions/More tabs inside `MainShell`) resolve it in tests.
///
/// The view model is wired into [app] first, so data assigned through the
/// provider's delegating setters (`app.wishlist = ...`) lands in the view
/// model and its listeners fire.
Widget wrapWithGoals(AppProvider app, Widget child) {
  final vm = buildGoalsViewModel();
  app.wireGoalsVm(vm);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppProvider>.value(value: app),
      ChangeNotifierProvider<GoalsViewModel>.value(value: vm),
    ],
    child: child,
  );
}
