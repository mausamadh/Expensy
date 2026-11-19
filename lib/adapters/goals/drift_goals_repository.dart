// lib/adapters/goals/drift_goals_repository.dart
//
// Drift-backed persistence adapter for the Goals bounded context (Phase 6).
//
// Thin wrapper over the existing AppDatabase wishlist / savings-goal /
// savings-contribution methods (which delegate to [AppDatabase.instance]) —
// no SQL changes.

import 'package:finwick/database/app_database.dart';
import 'package:finwick/domain/goals/ports/goals_repository.dart';
import 'package:finwick/models/models.dart';

class DriftGoalsRepository implements GoalsRepository {
  const DriftGoalsRepository();

  // ── Wishlist ──────────────────────────────────────────────────────────
  @override
  Future<List<WishlistItem>> getAllWishlist() =>
      AppDatabase.instance.getWishlist();

  @override
  Future<void> insertWishlist(WishlistItem item) =>
      AppDatabase.instance.insertWishlist(item);

  @override
  Future<void> updateWishlist(WishlistItem item) =>
      AppDatabase.instance.updateWishlist(item);

  @override
  Future<void> deleteWishlist(String id) =>
      AppDatabase.instance.deleteWishlist(id);

  // ── Savings goals ─────────────────────────────────────────────────────
  @override
  Future<List<SavingsGoal>> getAllGoals() =>
      AppDatabase.instance.getSavingsGoals();

  @override
  Future<void> insertGoal(SavingsGoal goal) =>
      AppDatabase.instance.insertSavingsGoal(goal);

  @override
  Future<void> updateGoal(SavingsGoal goal) =>
      AppDatabase.instance.updateSavingsGoal(goal);

  @override
  Future<void> deleteGoal(String id) =>
      AppDatabase.instance.deleteSavingsGoal(id);

  // ── Savings contributions ─────────────────────────────────────────────
  @override
  Future<List<SavingsContribution>> getAllContributions() =>
      AppDatabase.instance.getAllSavingsContributions();
}
