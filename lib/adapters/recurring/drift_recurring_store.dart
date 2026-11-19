// lib/adapters/recurring/drift_recurring_store.dart
//
// Drift-backed read+write adapter for the Recurring bounded context
// (Phase 6). Thin wrapper over the existing AppDatabase methods — no SQL
// changes.

import 'package:finwick/database/app_database.dart';
import 'package:finwick/domain/recurring/ports/recurring_store.dart';
import 'package:finwick/models/models.dart';

class DriftRecurringStore implements RecurringStore {
  const DriftRecurringStore();

  @override
  Future<List<RecurringPayment>> getRecurring() =>
      AppDatabase.instance.getRecurring();

  @override
  Future<void> insertRecurring(RecurringPayment r) =>
      AppDatabase.instance.insertRecurring(r);

  @override
  Future<void> updateRecurring(RecurringPayment r) =>
      AppDatabase.instance.updateRecurring(r);

  @override
  Future<void> deleteRecurring(String id) =>
      AppDatabase.instance.deleteRecurring(id);

  @override
  Future<List<RecurringHistoryEntry>> getRecurringHistory(String recurringId) =>
      AppDatabase.instance.getRecurringHistory(recurringId);

  @override
  Future<List<RecurringHistoryEntry>> getAllRecurringHistory() =>
      AppDatabase.instance.getAllRecurringHistory();

  @override
  Future<int> getRecurringHistoryCount() =>
      AppDatabase.instance.getRecurringHistoryCount();

  @override
  Future<void> insertRecurringHistory(RecurringHistoryEntry e) =>
      AppDatabase.instance.insertRecurringHistory(e);

  @override
  Future<void> deleteRecurringHistoryFor(String recurringId) =>
      AppDatabase.instance.deleteRecurringHistoryFor(recurringId);
}
