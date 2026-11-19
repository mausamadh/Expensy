// lib/domain/recurring/ports/recurring_store.dart
//
// Read+write port for the Recurring bounded context (Phase 6).
//
// The view model owns the `recurring` list and the recurring-history cache,
// and reloads the list after every mutation, so this store combines the read
// side (`getRecurring`, `getRecurringHistory`, …) with the write side
// (mirroring the `BudgetStore` / `CategoryStore` precedent).
//
// Pure Dart: imports only the shared models. The concrete Drift adapter
// lives in `adapters/` and is injected by the composition root.

import 'package:finwick/models/models.dart';

abstract interface class RecurringStore {
  // ── Recurring payments ────────────────────────────────────────────────
  Future<List<RecurringPayment>> getRecurring();
  Future<void> insertRecurring(RecurringPayment r);
  Future<void> updateRecurring(RecurringPayment r);
  Future<void> deleteRecurring(String id);

  // ── Recurring history ─────────────────────────────────────────────────
  Future<List<RecurringHistoryEntry>> getRecurringHistory(String recurringId);
  Future<List<RecurringHistoryEntry>> getAllRecurringHistory();
  Future<int> getRecurringHistoryCount();
  Future<void> insertRecurringHistory(RecurringHistoryEntry e);
  Future<void> deleteRecurringHistoryFor(String recurringId);
}
