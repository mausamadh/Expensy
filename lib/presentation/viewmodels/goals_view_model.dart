// lib/presentation/viewmodels/goals_view_model.dart
//
// Presentation-layer view model for the Goals bounded context (Phase 6,
// "Slim the provider") — wishlist items, savings goals, and the savings
// contributions that fund them.
//
// Owns the three state slices (`wishlist`, `savingsGoals`,
// `savingsContributions`) and delegates every mutation to the
// [GoalsRepository] port. Replaces the wishlist + savings-goal CRUD/bridge
// slice of `AppProvider`.
//
// Note: the ledger-coupled operations — `contributeToGoal`,
// `withdrawFromGoal`, and `purchaseWishlistItem` — stay on `AppProvider`
// because they mutate account balances and the transaction ledger.
//
// Layering: this file lives in `presentation/` and imports only `domain/`
// and `models/` — never `adapters/` or `database/`. The repository is
// injected through the constructor by the composition root.
import 'package:flutter/foundation.dart';

import 'package:finwick/domain/goals/ports/goals_repository.dart';
import 'package:finwick/domain/shared/uuid.dart';
import 'package:finwick/models/models.dart';

class GoalsViewModel extends ChangeNotifier {
  GoalsViewModel({required GoalsRepository repository})
      : _repo = repository,
        _uuid = Uuid();

  final GoalsRepository _repo;
  final Uuid _uuid;

  // ── State ──────────────────────────────────────────────────────────────
  List<WishlistItem> _wishlist = [];
  List<SavingsGoal> _savingsGoals = [];
  List<SavingsContribution> _savingsContributions = [];

  /// All wishlist items (creation order, newest first per the DB query).
  List<WishlistItem> get wishlist => _wishlist;

  /// Replaces the wishlist (fresh-list reactivity rule: reassign, never
  /// mutate in place) and notifies listeners.
  set wishlist(List<WishlistItem> next) {
    _wishlist = next;
    notifyListeners();
  }

  /// All savings goals (creation order, oldest first per the DB query).
  List<SavingsGoal> get savingsGoals => _savingsGoals;

  /// Replaces the savings-goal list and notifies listeners.
  set savingsGoals(List<SavingsGoal> next) {
    _savingsGoals = next;
    notifyListeners();
  }

  /// All savings contributions (date, newest first per the DB query).
  List<SavingsContribution> get savingsContributions => _savingsContributions;

  /// Replaces the savings-contribution list and notifies listeners.
  set savingsContributions(List<SavingsContribution> next) {
    _savingsContributions = next;
    notifyListeners();
  }

  // ── Wishlist mutations ─────────────────────────────────────────────────
  Future<void> addWishlist(WishlistItem w) async {
    await _repo.insertWishlist(w);
    _wishlist = await _repo.getAllWishlist();
    notifyListeners();
  }

  Future<void> updateWishlist(WishlistItem w) async {
    await _repo.updateWishlist(w);
    _wishlist = await _repo.getAllWishlist();
    notifyListeners();
  }

  /// Deletes a wishlist item, first unlinking any savings goal that points
  /// at it so the goal is left in a valid (unlinked) state.
  Future<void> deleteWishlist(String id) async {
    for (final g in _savingsGoals.where((g) => g.wishlistItemId == id)) {
      await _repo.updateGoal(g.copyWith(clearWishlistItemId: true));
    }
    _savingsGoals = await _repo.getAllGoals();
    await _repo.deleteWishlist(id);
    _wishlist = await _repo.getAllWishlist();
    notifyListeners();
  }

  Future<VoidCallback> deleteWishlistWithUndo(String id) async {
    final item = _wishlist.firstWhere((w) => w.id == id);
    await deleteWishlist(id);
    return () async {
      await addWishlist(item);
    };
  }

  // ── Savings-goal mutations ─────────────────────────────────────────────
  Future<void> addSavingsGoal(SavingsGoal g) async {
    await _repo.insertGoal(g);
    _savingsGoals = await _repo.getAllGoals();
    notifyListeners();
  }

  Future<void> updateSavingsGoal(SavingsGoal g) async {
    await _repo.updateGoal(g);
    _savingsGoals = await _repo.getAllGoals();
    notifyListeners();
  }

  /// Deletes a savings goal, first unlinking any wishlist item that points
  /// at it so the item is left in a valid (unlinked) state.
  Future<void> deleteSavingsGoal(String id) async {
    for (final w in _wishlist.where((w) => w.goalId == id)) {
      await _repo.updateWishlist(w.copyWith(clearGoalId: true));
    }
    _wishlist = await _repo.getAllWishlist();
    await _repo.deleteGoal(id);
    _savingsGoals = await _repo.getAllGoals();
    notifyListeners();
  }

  Future<VoidCallback> deleteSavingsGoalWithUndo(String id) async {
    final s = _savingsGoals.firstWhere((s) => s.id == id);
    await deleteSavingsGoal(id);
    return () async {
      await addSavingsGoal(s);
    };
  }

  // ── Goal ↔ wishlist bridge ─────────────────────────────────────────────
  SavingsGoal? goalForWishlist(WishlistItem item) {
    if (item.goalId == null) return null;
    return _savingsGoals.where((g) => g.id == item.goalId).firstOrNull;
  }

  WishlistItem? wishlistForGoal(SavingsGoal goal) {
    if (goal.wishlistItemId == null) return null;
    return _wishlist.where((w) => w.id == goal.wishlistItemId).firstOrNull;
  }

  Future<void> createGoalForWishlist(WishlistItem item, SavingsGoal goal) async {
    final updatedGoal = goal.copyWith(wishlistItemId: item.id);
    final updatedItem = item.copyWith(goalId: goal.id);
    await _repo.insertGoal(updatedGoal);
    await _repo.updateWishlist(updatedItem);
    _savingsGoals = await _repo.getAllGoals();
    _wishlist = await _repo.getAllWishlist();
    notifyListeners();
  }

  Future<void> unlinkWishlistAndGoal({
    required String wishlistItemId,
    required String goalId,
  }) async {
    final w = _wishlist.where((x) => x.id == wishlistItemId).firstOrNull;
    if (w != null) {
      await _repo.updateWishlist(w.copyWith(clearGoalId: true));
    }
    final g = _savingsGoals.where((x) => x.id == goalId).firstOrNull;
    if (g != null) {
      await _repo.updateGoal(g.copyWith(clearWishlistItemId: true));
    }
    _wishlist = await _repo.getAllWishlist();
    _savingsGoals = await _repo.getAllGoals();
    notifyListeners();
  }

  // ── Read helpers ───────────────────────────────────────────────────────
  List<SavingsContribution> contributionsFor(String goalId) {
    return _savingsContributions.where((c) => c.goalId == goalId).toList();
  }

  /// Generates a new UUID for a new goal / wishlist item.
  String newId() => _uuid.v4();
}
