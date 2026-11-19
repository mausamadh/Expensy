// lib/domain/goals/ports/goals_repository.dart
//
// Domain port for the Goals bounded context (Phase 6) — wishlist items,
// savings goals, and the savings contributions that fund them.
//
// Pure Dart: imports only the shared models. The concrete Drift adapter
// lives in `adapters/` and is injected by the composition root.
//
// Note: the ledger-coupled operations (contributing to / withdrawing from a
// goal, purchasing a wishlist item) are NOT part of this port — they mutate
// account balances and stay on the ledger side of the app.

import 'package:finwick/models/models.dart';

abstract interface class GoalsRepository {
  // ── Wishlist ──────────────────────────────────────────────────────────
  Future<List<WishlistItem>> getAllWishlist();
  Future<void> insertWishlist(WishlistItem item);
  Future<void> updateWishlist(WishlistItem item);
  Future<void> deleteWishlist(String id);

  // ── Savings goals ─────────────────────────────────────────────────────
  Future<List<SavingsGoal>> getAllGoals();
  Future<void> insertGoal(SavingsGoal goal);
  Future<void> updateGoal(SavingsGoal goal);
  Future<void> deleteGoal(String id);

  // ── Savings contributions (read-only here) ────────────────────────────
  Future<List<SavingsContribution>> getAllContributions();
}
