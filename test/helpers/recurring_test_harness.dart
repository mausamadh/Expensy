// test/helpers/recurring_test_harness.dart
//
// Shared widget-test harness for the Recurring view model (Phase 6).
//
// Several screens read the delegated recurring getters (`app.recurring`,
// `app.recurringHistoryCount`, `app.recurringDueOnDay`, `app.getHistoryFor`)
// through `RecurringViewModel`. Widget tests that mount those screens must
// therefore provide a `RecurringViewModel` in addition to `AppProvider`.
// This helper builds a VM backed by an in-memory fake store (no DB) and wraps
// a child in a `MultiProvider` exposing both notifiers.
//
// The cross-cutting hooks (addTransaction, addTransfer, newId, accountById,
// settings currency, net-worth snapshot) read straight off the [AppProvider]
// so the VM's behavior stays consistent with the provider's own state in
// tests. The auto-pay processor is constructed over the in-memory test DB
// (set via `AppDatabase.setInstanceForTesting`), matching production wiring.

import 'package:finwick/database/app_database.dart';
import 'package:finwick/domain/recurring/ports/recurring_store.dart';
import 'package:finwick/models/models.dart';
import 'package:finwick/presentation/viewmodels/recurring_view_model.dart';
import 'package:finwick/providers/app_provider.dart';
import 'package:finwick/services/recurring_payment_processor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// In-memory [RecurringStore] for widget tests — no DB access.
class InMemoryRecurringStore implements RecurringStore {
  List<RecurringPayment> _recurring = [];
  List<RecurringHistoryEntry> _history = [];

  @override
  Future<List<RecurringPayment>> getRecurring() async =>
      List.unmodifiable(_recurring);

  @override
  Future<void> insertRecurring(RecurringPayment r) async {
    _recurring = [..._recurring, r];
  }

  @override
  Future<void> updateRecurring(RecurringPayment r) async {
    _recurring = [for (final x in _recurring) x.id == r.id ? r : x];
  }

  @override
  Future<void> deleteRecurring(String id) async {
    _recurring = [for (final x in _recurring) if (x.id != id) x];
  }

  @override
  Future<List<RecurringHistoryEntry>> getRecurringHistory(
          String recurringId) async =>
      List.unmodifiable(
          [for (final h in _history) if (h.recurringId == recurringId) h]);

  @override
  Future<List<RecurringHistoryEntry>> getAllRecurringHistory() async =>
      List.unmodifiable(_history);

  @override
  Future<int> getRecurringHistoryCount() async => _history.length;

  @override
  Future<void> insertRecurringHistory(RecurringHistoryEntry e) async {
    _history = [..._history, e];
  }

  @override
  Future<void> deleteRecurringHistoryFor(String recurringId) async {
    _history = [for (final h in _history) if (h.recurringId != recurringId) h];
  }
}

/// Builds a [RecurringViewModel] backed by an in-memory fake store, with the
/// cross-cutting hooks wired to [app] so the VM's behavior sees the same
/// ledger state the provider exposes.
RecurringViewModel buildRecurringViewModel(AppProvider app) => RecurringViewModel(
      store: InMemoryRecurringStore(),
      processor: RecurringPaymentProcessor(AppDatabase.instance),
      refreshLedger: () async {
        app.transactions = await AppDatabase.instance.getTransactions();
        app.accounts = await AppDatabase.instance.getAccounts();
      },
      addTransaction: (t) => app.addTransaction(t),
      addTransfer: ({
        required String fromId,
        required String toId,
        required double fromAmount,
        double? toAmount,
        String note = '',
        String? title,
        DateTime? date,
      }) =>
          app.addTransfer(
            fromId: fromId,
            toId: toId,
            fromAmount: fromAmount,
            toAmount: toAmount,
            note: note,
            title: title,
            date: date,
          ),
      newId: app.newId,
      accountById: app.accountById,
      settingsCurrency: () => app.settings.currency,
      recordNetWorthSnapshot: app.recordNetWorthSnapshot,
      scheduleReminder: (r, currency) async {},
      cancelReminder: (id) async {},
      serializeMutation: <T>(Future<T> Function() action) => action(),
    );

/// Wraps [child] in a `MultiProvider` exposing [app] and a fresh
/// [RecurringViewModel], so screens that watch the recurring view model
/// resolve it in tests.
///
/// The view model is wired into [app] first, so data assigned through the
/// provider's delegating setters (`app.recurring = ...`) lands in the view
/// model and its listeners fire.
Widget wrapWithRecurring(AppProvider app, Widget child) {
  final vm = buildRecurringViewModel(app);
  app.wireRecurringVm(vm);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppProvider>.value(value: app),
      ChangeNotifierProvider<RecurringViewModel>.value(value: vm),
    ],
    child: child,
  );
}
