// lib/adapters/ledger/drift_ledger_repositories.dart
//
// Drift-backed read adapters for the Ledger bounded context (Phase 2a).
//
// Thin wrappers over the existing [DBHelper] statics (which delegate to
// [AppDatabase.instance]) — no SQL changes. `getById` is an in-memory lookup
// over `getAll` to avoid adding new queries.

import 'package:finwick/database/db_helper.dart';
import 'package:finwick/domain/ledger/ports/ports.dart';
import 'package:finwick/models/models.dart';

class DriftAccountRepository implements AccountRepository {
  const DriftAccountRepository();

  @override
  Future<List<Account>> getAll() => DBHelper.getAccounts();

  @override
  Future<Account?> getById(String id) async {
    for (final a in await DBHelper.getAccounts()) {
      if (a.id == id) return a;
    }
    return null;
  }
}

class DriftCategoryRepository implements CategoryRepository {
  const DriftCategoryRepository();

  @override
  Future<List<AppCategory>> getAll() => DBHelper.getCategories();

  @override
  Future<AppCategory?> getById(String id) async {
    for (final c in await DBHelper.getCategories()) {
      if (c.id == id) return c;
    }
    return null;
  }
}

class DriftTransactionRepository implements TransactionRepository {
  const DriftTransactionRepository();

  @override
  Future<List<AppTransaction>> getAll({int? limit, int offset = 0}) =>
      DBHelper.getTransactions(limit: limit, offset: offset);

  @override
  Future<List<AppTransaction>> getByAccount(
    String accountId, {
    int? limit,
    int offset = 0,
  }) =>
      DBHelper.getTransactionsForAccount(accountId,
          limit: limit, offset: offset);

  @override
  Future<List<TransactionSplit>> getAllSplits() => DBHelper.getAllSplits();

  @override
  Future<List<TransactionSplit>> getSplitsForTransaction(String transactionId) =>
      DBHelper.getSplitsForTransaction(transactionId);
}
