// lib/presentation/viewmodels/recurring_view_model.dart
//
// Presentation-layer view model for the Recurring bounded context (Phase 6,
// "Slim the provider") — the user's recurring payments, their history, and
// the auto-pay scheduling / catch-up over them.
//
// Owns the `recurring` list, the `recurringHistoryCount`, the lazy
// recurring-history cache, and the auto-pay timer. Every mutation is
// delegated to the [RecurringStore] port and serialized through the
// provider's zone-based mutation mutex so recurring writes stay atomic with
// the provider's own ledger writes.
//
// Cross-cutting couplings are injected as functions rather than a provider
// reference, keeping this file free of any `providers/` or `database/`
// import:
//   * [processor] — the shared [RecurringPaymentProcessor] (idempotency
//     checks + auto-pay catch-up), constructed over the DB by the
//     composition root.
//   * [addTransaction] / [addTransfer] — create the ledger entry when a
//     recurring payment is marked paid.
//   * [newId] — id generator (shared with the provider).
//   * [accountById] — resolves an account id to an account (currency lookup).
//   * [settingsCurrency] — main currency for history entries / reminders.
//   * [recordNetWorthSnapshot] — net-worth snapshot after auto-pay.
//   * [refreshLedger] — reload transactions + accounts after auto-pay.
//   * [scheduleReminder] / [cancelReminder] — notification scheduling.
//   * [serializeMutation] — the provider's zone-based mutation mutex.
//
// Layering: this file lives in `presentation/` and imports only `domain/`,
// `models/`, and the shared `services/` processor — never `adapters/` or
// `database/`. The store and processor are injected through the constructor
// by the composition root.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:finwick/domain/recurring/ports/recurring_store.dart';
import 'package:finwick/models/models.dart';
import 'package:finwick/services/recurring_payment_processor.dart';

class RecurringViewModel extends ChangeNotifier {
  RecurringViewModel({
    required RecurringStore store,
    required RecurringPaymentProcessor processor,
    required Future<void> Function() refreshLedger,
    required Future<void> Function(AppTransaction t) addTransaction,
    required Future<AppTransaction?> Function({
      required String fromId,
      required String toId,
      required double fromAmount,
      double? toAmount,
      String note,
      String? title,
      DateTime? date,
    }) addTransfer,
    required String Function() newId,
    required Account? Function(String id) accountById,
    required String Function() settingsCurrency,
    required Future<void> Function() recordNetWorthSnapshot,
    required Future<void> Function(RecurringPayment r, String currency)
        scheduleReminder,
    required Future<void> Function(String id) cancelReminder,
    required Future<T> Function<T>(Future<T> Function()) serializeMutation,
  })  : _store = store,
        _processor = processor,
        _refreshLedger = refreshLedger,
        _addTransaction = addTransaction,
        _addTransfer = addTransfer,
        _newId = newId,
        _accountById = accountById,
        _settingsCurrency = settingsCurrency,
        _recordNetWorthSnapshot = recordNetWorthSnapshot,
        _scheduleReminder = scheduleReminder,
        _cancelReminder = cancelReminder,
        _serializeMutation = serializeMutation;

  final RecurringStore _store;
  final RecurringPaymentProcessor _processor;
  final Future<void> Function() _refreshLedger;
  final Future<void> Function(AppTransaction t) _addTransaction;
  final Future<AppTransaction?> Function({
    required String fromId,
    required String toId,
    required double fromAmount,
    double? toAmount,
    String note,
    String? title,
    DateTime? date,
  }) _addTransfer;
  final String Function() _newId;
  final Account? Function(String id) _accountById;
  final String Function() _settingsCurrency;
  final Future<void> Function() _recordNetWorthSnapshot;
  final Future<void> Function(RecurringPayment r, String currency)
      _scheduleReminder;
  final Future<void> Function(String id) _cancelReminder;
  final Future<T> Function<T>(Future<T> Function()) _serializeMutation;

  // ── State ──────────────────────────────────────────────────────────────
  List<RecurringPayment> _recurring = [];

  /// All recurring payments (creation order per the DB query).
  List<RecurringPayment> get recurring => _recurring;

  /// Replaces the recurring list (fresh-list reactivity rule: reassign, never
  /// mutate in place) and notifies listeners.
  set recurring(List<RecurringPayment> next) {
    _recurring = next;
    notifyListeners();
  }

  /// Total row count in `recurring_history` — kept for display purposes
  /// (e.g. the Backup screen's "what's included" list) without needing to
  /// load every history row for every recurring payment into memory.
  int _recurringHistoryCount = 0;

  int get recurringHistoryCount => _recurringHistoryCount;

  set recurringHistoryCount(int value) {
    _recurringHistoryCount = value;
  }

  // ── Recurring history (lazy cache) ────────────────────────────────────
  final Map<String, List<RecurringHistoryEntry>> _historyCache = {};

  Timer? _autoPayTimer;

  // ── Mutations ──────────────────────────────────────────────────────────
  Future<void> addRecurring(RecurringPayment r) async {
    await _store.insertRecurring(r);
    _recurring = await _store.getRecurring();
    notifyListeners();
    if (r.reminderEnabled) {
      await _scheduleReminder(r, _settingsCurrency());
    }
    if (r.autoPayEnabled) {
      await checkAndProcessAutoPay();
    }
  }

  Future<void> updateRecurring(RecurringPayment r) async {
    await _cancelReminder(r.id);
    await _store.updateRecurring(r);
    _recurring = await _store.getRecurring();
    notifyListeners();
    if (r.reminderEnabled) {
      await _scheduleReminder(r, _settingsCurrency());
    }
    if (r.autoPayEnabled) {
      await checkAndProcessAutoPay();
    }
  }

  Future<void> deleteRecurring(String id) async {
    await _cancelReminder(id);
    await _store.deleteRecurring(id);
    await _store.deleteRecurringHistoryFor(id);
    _historyCache.remove(id);
    _recurring = await _store.getRecurring();
    _recurringHistoryCount = await _store.getRecurringHistoryCount();
    notifyListeners();
  }

  /// Deletes a recurring payment and returns an undo callback that re-inserts
  /// it along with its history.
  Future<VoidCallback> deleteRecurringWithUndo(String id) async {
    final rec = _recurring.firstWhere((r) => r.id == id);
    final history = await _store.getRecurringHistory(id);
    await deleteRecurring(id);
    return () async {
      await addRecurring(rec);
      for (final h in history) {
        await _store.insertRecurringHistory(h);
      }
      _historyCache.remove(id);
      _recurringHistoryCount = await _store.getRecurringHistoryCount();
      notifyListeners();
    };
  }

  Future<void> markRecurringPaid(RecurringPayment r,
      {DateTime? occurrenceDate}) async {
    await _serializeMutation(() async {
      final effectiveDate = occurrenceDate ?? r.nextDate;
      // Idempotency guard (B10): skip if this cycle date was already paid
      // (e.g. by auto-pay).
      if (await _processor.hasHistoryForDate(r.id, effectiveDate,
          action: 'paid')) {
        return;
      }

      final txDate = occurrenceDate ?? DateTime.now();
      if (r.isTransfer) {
        if (r.toAccountId == null || r.toAccountId!.isEmpty) return;
        await _addTransfer(
          fromId: r.accountId,
          toId: r.toAccountId!,
          fromAmount: r.amount,
          toAmount: r.toAmount,
          note: r.notes,
          title: r.name,
          date: txDate,
        );
      } else {
        final t = AppTransaction(
          id: _newId(),
          type: r.paymentType,
          amount: r.amount,
          description: '${r.name} (recurring)',
          accountId: r.accountId,
          categoryId: r.categoryId,
          date: txDate,
        );
        await _addTransaction(t);
      }
      await _recordHistory(r, 'paid', date: effectiveDate);

      final updated = r.copyWith(
        nextDate: r.calcNextDate(),
        paidPayments: r.paidPayments + 1,
      );
      await _store.updateRecurring(updated);
      final idx = _recurring.indexWhere((item) => item.id == r.id);
      if (idx != -1) {
        final nextRec = List<RecurringPayment>.from(_recurring);
        nextRec[idx] = updated;
        _recurring = nextRec;
      }
      notifyListeners();
      await _cancelReminder(r.id);
      await _scheduleReminder(updated, _settingsCurrency());
    });
  }

  Future<void> skipNextRecurring(RecurringPayment r) async {
    await _serializeMutation(() async {
      if (await _processor.hasHistoryForDate(r.id, r.nextDate)) {
        return;
      }
      await _recordHistory(r, 'skipped', date: r.nextDate);

      final updated = r.copyWith(
        nextDate: r.calcNextDate(),
        paidPayments: r.paidPayments + 1,
      );
      await _store.updateRecurring(updated);
      final idx = _recurring.indexWhere((item) => item.id == r.id);
      if (idx != -1) {
        final nextRec = List<RecurringPayment>.from(_recurring);
        nextRec[idx] = updated;
        _recurring = nextRec;
      }
      notifyListeners();
      await _cancelReminder(r.id);
      await _scheduleReminder(updated, _settingsCurrency());
    });
  }

  /// Automatically marks any recurring items paid if they are due today or
  /// overdue and have auto-pay enabled, using the shared
  /// [RecurringPaymentProcessor].
  Future<void> checkAndProcessAutoPay() async {
    await _serializeMutation(() async {
      final processed = await _processor.processDuePayments();
      if (processed.isNotEmpty) {
        await _refreshLedger();
        _recurring = await _store.getRecurring();
        _historyCache.clear();
        _recurringHistoryCount = await _store.getRecurringHistoryCount();
        notifyListeners();
        await _recordNetWorthSnapshot();
      }
    });
  }

  // ── Recurring History ─────────────────────────────────────────────────

  Future<void> _recordHistory(RecurringPayment r, String action,
      {DateTime? date}) async {
    final acct = _accountById(r.accountId);
    final entry = RecurringHistoryEntry(
      id: _newId(),
      recurringId: r.id,
      action: action,
      date: date ?? DateTime.now(),
      amount: r.amount,
      currency: acct?.currency ?? _settingsCurrency(),
    );
    await _store.insertRecurringHistory(entry);
    _historyCache.remove(r.id); // invalidate cache for this payment
    _recurringHistoryCount = await _store.getRecurringHistoryCount();
  }

  /// Loads history for [recurringId] from the store, caching in memory.
  /// Returns immediately if already cached.
  Future<List<RecurringHistoryEntry>> getHistoryFor(String recurringId) async {
    if (_historyCache.containsKey(recurringId)) {
      return _historyCache[recurringId]!;
    }
    final entries = await _store.getRecurringHistory(recurringId);
    _historyCache[recurringId] = entries;
    return entries;
  }

  /// Clears the in-memory history cache (e.g. after a backup restore).
  void clearHistoryCache() {
    _historyCache.clear();
  }

  // ── Read helpers ───────────────────────────────────────────────────────
  /// Recurring payments whose next due date falls on [day].
  List<RecurringPayment> recurringDueOnDay(DateTime day) {
    return _recurring.where((r) =>
        r.nextDate.year == day.year &&
        r.nextDate.month == day.month &&
        r.nextDate.day == day.day).toList();
  }

  // ── Auto-pay timer ─────────────────────────────────────────────────────
  /// Schedules a one-shot evaluation timer for the next upcoming auto-pay
  /// payment rather than running a battery-draining continuous 1-minute
  /// periodic timer.
  void scheduleNextAutoPayTimer() {
    _autoPayTimer?.cancel();
    _autoPayTimer = null;

    final autoPayItems = _recurring.where((r) => r.autoPayEnabled).toList();
    if (autoPayItems.isEmpty) return;

    final now = DateTime.now();
    DateTime? earliestDue;

    for (final item in autoPayItems) {
      final parts = item.autoPayTime.split(':');
      final hour = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 9) : 9;
      final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

      final nextD = item.nextDate;
      var candidate = DateTime(nextD.year, nextD.month, nextD.day, hour, minute);
      if (candidate.isBefore(now)) {
        earliestDue = now;
        break;
      }
      if (earliestDue == null || candidate.isBefore(earliestDue)) {
        earliestDue = candidate;
      }
    }

    if (earliestDue != null) {
      final delay = earliestDue.isBefore(now)
          ? Duration.zero
          : earliestDue.difference(now);
      _autoPayTimer = Timer(delay, () async {
        await checkAndProcessAutoPay();
        scheduleNextAutoPayTimer();
      });
    }
  }

  /// Starts evaluation for auto-pay via next-due timer.
  void startAutoPayTimer() => scheduleNextAutoPayTimer();

  /// Pauses the auto-pay timer while the application is in the background or
  /// paused to save battery.
  void pauseAutoPayTimer() {
    _autoPayTimer?.cancel();
    _autoPayTimer = null;
  }

  @override
  void dispose() {
    pauseAutoPayTimer();
    super.dispose();
  }
}
