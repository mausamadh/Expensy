// lib/domain/ledger/ports/ports.dart
//
// Read-side ports for the Ledger bounded context (hexagonal architecture,
// HEXAGONAL_MIGRATION_PLAN.md §4.1 / §5 Phase 2a).
//
// Domain-owned interfaces: the application layer programs against these, and
// Drift adapters (lib/adapters/ledger/) provide the concrete implementations
// over the existing AppDatabase. No Flutter, Drift, or plugin imports here
// (enforced by ci_guard).
//
// Phase 2a covers the read side only. The write side (AddTransaction,
// AddTransfer, …) is added in Phase 2b.

import 'package:finwick/models/models.dart';

/// Read access to accounts.
abstract interface class AccountRepository {
  /// All accounts in display order.
  Future<List<Account>> getAll();

  /// A single account by id, or null if absent.
  Future<Account?> getById(String id);
}

/// Read access to categories (including hidden system categories).
abstract interface class CategoryRepository {
  /// All categories in display order.
  Future<List<AppCategory>> getAll();

  /// A single category by id, or null if absent.
  Future<AppCategory?> getById(String id);
}

/// Read access to transactions and their splits.
abstract interface class TransactionRepository {
  /// All transactions, newest first, optionally paged.
  Future<List<AppTransaction>> getAll({int? limit, int offset = 0});

  /// Transactions for one account, newest first, optionally paged.
  Future<List<AppTransaction>> getByAccount(
    String accountId, {
    int? limit,
    int offset = 0,
  });

  /// All split lines, grouped by parent transaction id.
  Future<List<TransactionSplit>> getAllSplits();

  /// Split lines for a single transaction.
  Future<List<TransactionSplit>> getSplitsForTransaction(String transactionId);
}
