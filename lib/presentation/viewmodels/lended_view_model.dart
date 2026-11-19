// lib/presentation/viewmodels/lended_view_model.dart
//
// Presentation-layer view model for the Lended bounded context (Phase 6,
// "Slim the provider") — the people you lend/borrow money to and the
// individual lend/borrow entries that form each person's ledger history.
//
// Owns the two state slices (`lendedPeople`, `lended`) and delegates every
// mutation to the [LendedRepository] port. Replaces the lended slice of
// `AppProvider`.
//
// Cross-cutting couplings are injected as functions rather than a provider
// reference, keeping this file free of any `providers/` import:
//   * [applyBalanceDelta] — atomic SQL balance delta (provider/DB hook),
//     used to reverse/apply unsettled lend/borrow effects on an account.
//   * [balanceAccountIdFor] — resolves a debit card to its linked account.
//   * [refreshAccounts] — reloads the provider's account list after a
//     balance-mutating lended operation.
//   * [onNetWorthChanged] — net-worth snapshot hook, fired after mutations.
//   * [personName] — resolves a person id to a display name (reminders).
//   * [currency] — the main currency (reminder scheduling).
//   * [serializeMutation] — the provider's zone-based mutation mutex, so
//     lended balance mutations serialize with the provider's own writes.
//
// Layering: this file lives in `presentation/` and imports only `domain/`,
// `models/`, and `services/` — never `adapters/` or `database/`. The
// repository is injected through the constructor by the composition root.
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'package:finwick/domain/lended/ports/lended_repository.dart';
import 'package:finwick/domain/shared/uuid.dart';
import 'package:finwick/models/models.dart';
import 'package:finwick/services/lended_notification_service.dart';

class LendedViewModel extends ChangeNotifier {
  LendedViewModel({
    required LendedRepository repository,
    required Future<void> Function(String accountId, double delta)
        applyBalanceDelta,
    required String Function(String accountId) balanceAccountIdFor,
    required Future<void> Function() refreshAccounts,
    required Future<void> Function() onNetWorthChanged,
    required String? Function(String personId) personName,
    required String Function() currency,
    required Future<T> Function<T>(Future<T> Function()) serializeMutation,
  })  : _repo = repository,
        _applyBalanceDelta = applyBalanceDelta,
        _balanceAccountIdFor = balanceAccountIdFor,
        _refreshAccounts = refreshAccounts,
        _onNetWorthChanged = onNetWorthChanged,
        _personName = personName,
        _currency = currency,
        _serializeMutation = serializeMutation,
        _uuid = Uuid();

  final LendedRepository _repo;
  final Future<void> Function(String accountId, double delta)
      _applyBalanceDelta;
  final String Function(String accountId) _balanceAccountIdFor;
  final Future<void> Function() _refreshAccounts;
  final Future<void> Function() _onNetWorthChanged;
  final String? Function(String personId) _personName;
  final String Function() _currency;
  final Future<T> Function<T>(Future<T> Function()) _serializeMutation;
  final Uuid _uuid;
  final LendedNotificationService _lendedNotif = LendedNotificationService();

  // ── State ──────────────────────────────────────────────────────────────
  List<LendedPerson> _lendedPeople = [];
  List<LendedMoney> _lended = [];

  /// All lended people (creation order, oldest first per the DB query).
  List<LendedPerson> get lendedPeople => _lendedPeople;

  /// Replaces the lended-people list (fresh-list reactivity rule: reassign,
  /// never mutate in place) and notifies listeners.
  set lendedPeople(List<LendedPerson> next) {
    _lendedPeople = next;
    notifyListeners();
  }

  /// All lended-money entries (date, newest first per the DB query).
  List<LendedMoney> get lended => _lended;

  /// Replaces the lended-money list and notifies listeners.
  set lended(List<LendedMoney> next) {
    _lended = next;
    notifyListeners();
  }

  // ── Lended people mutations ────────────────────────────────────────────
  Future<void> addLendedPerson(LendedPerson p) async {
    await _repo.insertLendedPerson(p);
    lendedPeople = await _repo.getLendedPeople();
  }

  Future<void> updateLendedPerson(LendedPerson p) async {
    await _repo.updateLendedPerson(p);
    lendedPeople = await _repo.getLendedPeople();
  }

  /// Deletes a person along with every lended-money entry that belongs to
  /// them, cancelling any pending reminders first, and reversing unsettled
  /// balances.
  Future<void> deleteLendedPerson(String id) async {
    await _serializeMutation(() async {
      for (final l in _lended.where((l) => l.personId == id)) {
        await _lendedNotif.cancelLendedReminder(l.id);
        if (l.accountId != null && !l.isSettled) {
          final delta = -_lendedBalanceEffect(l);
          if (delta != 0) {
            final target = _balanceAccountIdFor(l.accountId!);
            await _applyBalanceDelta(target, delta);
          }
        }
      }
      await _repo.deleteLendedForPerson(id);
      await _repo.deleteLendedPerson(id);
      lended = await _repo.getLended();
      lendedPeople = await _repo.getLendedPeople();
      await _refreshAccounts();
      await _onNetWorthChanged();
    });
  }

  // ── Lended money mutations ─────────────────────────────────────────────
  Future<void> addLended(LendedMoney l) async {
    await _serializeMutation(() async {
      await _repo.insertLended(l);
      if (l.accountId != null) {
        final delta = _lendedBalanceEffect(l);
        if (delta != 0) {
          final target = _balanceAccountIdFor(l.accountId!);
          await _applyBalanceDelta(target, delta);
        }
      }
      lended = await _repo.getLended();
      await _refreshAccounts();
      await _onNetWorthChanged();
      if (l.reminderEnabled && l.dueDate != null) {
        await _lendedNotif.scheduleLendedReminder(
          l,
          _currency(),
          personName: _personName(l.personId) ?? '',
        );
      }
    });
  }

  Future<void> updateLended(LendedMoney updated, LendedMoney original) async {
    await _serializeMutation(() async {
      final oldEffect = _lendedBalanceEffect(original);
      final newEffect = _lendedBalanceEffect(updated);
      final oldAcc = original.accountId != null
          ? _balanceAccountIdFor(original.accountId!)
          : null;
      final newAcc = updated.accountId != null
          ? _balanceAccountIdFor(updated.accountId!)
          : null;

      if (oldAcc != null && oldAcc == newAcc) {
        final netDelta = newEffect - oldEffect;
        if (netDelta != 0) {
          await _applyBalanceDelta(oldAcc, netDelta);
        }
      } else {
        if (oldAcc != null && oldEffect != 0) {
          await _applyBalanceDelta(oldAcc, -oldEffect);
        }
        if (newAcc != null && newEffect != 0) {
          await _applyBalanceDelta(newAcc, newEffect);
        }
      }

      await _repo.updateLended(updated);
      lended = await _repo.getLended();
      await _refreshAccounts();
      await _onNetWorthChanged();
      // Always cancel old reminder, then reschedule if still enabled.
      await _lendedNotif.cancelLendedReminder(original.id);
      if (updated.reminderEnabled && updated.dueDate != null && !updated.isSettled) {
        await _lendedNotif.scheduleLendedReminder(
          updated,
          _currency(),
          personName: _personName(updated.personId) ?? '',
        );
      }
    });
  }

  Future<void> settleLended(LendedMoney l) async {
    await _serializeMutation(() async {
      if (l.accountId != null && !l.isSettled) {
        final delta = -_lendedBalanceEffect(l);
        if (delta != 0) {
          final target = _balanceAccountIdFor(l.accountId!);
          await _applyBalanceDelta(target, delta);
        }
      }
      final settled = l.copyWith(isSettled: true);
      await _repo.updateLended(settled);
      lended = await _repo.getLended();
      await _refreshAccounts();
      await _onNetWorthChanged();
      await _lendedNotif.cancelLendedReminder(l.id);
    });
  }

  Future<void> deleteLended(String id) async {
    await _serializeMutation(() async {
      final idx = _lended.indexWhere((l) => l.id == id);
      if (idx != -1) {
        final record = _lended[idx];
        if (record.accountId != null && !record.isSettled) {
          final delta = -_lendedBalanceEffect(record);
          if (delta != 0) {
            final target = _balanceAccountIdFor(record.accountId!);
            await _applyBalanceDelta(target, delta);
          }
        }
      }
      await _lendedNotif.cancelLendedReminder(id);
      await _repo.deleteLended(id);
      lended = await _repo.getLended();
      await _refreshAccounts();
      await _onNetWorthChanged();
    });
  }

  /// Deletes a lended entry and returns an undo callback that re-inserts it
  /// (re-applying its balance effect and rescheduling its reminder).
  Future<VoidCallback> deleteLendedWithUndo(String id) async {
    final record = _lended.firstWhere((l) => l.id == id);
    await deleteLended(id);
    return () async {
      await _serializeMutation(() async {
        await _repo.insertLended(record);
        if (record.accountId != null && !record.isSettled) {
          final delta = _lendedBalanceEffect(record);
          if (delta != 0) {
            final target = _balanceAccountIdFor(record.accountId!);
            await _applyBalanceDelta(target, delta);
          }
        }
        lended = await _repo.getLended();
        await _refreshAccounts();
        if (!record.isSettled) {
          final p = _lendedPeople
              .where((p) => p.id == record.personId)
              .firstOrNull;
          if (p != null) {
            _lendedNotif.scheduleLendedReminder(
              record,
              _currency(),
              personName: p.name,
            );
          }
        }
        await _onNetWorthChanged();
      });
    };
  }

  /// Deletes a person (and their entries) and returns an undo callback that
  /// re-adds the person and every one of their entries.
  Future<VoidCallback> deleteLendedPersonWithUndo(String id) async {
    final person = _lendedPeople.firstWhere((p) => p.id == id);
    final personLended = _lended.where((l) => l.personId == id).toList();

    await deleteLendedPerson(id);
    return () async {
      await addLendedPerson(person);
      for (final l in personLended) {
        await addLended(l);
      }
    };
  }

  // ── Read helpers ───────────────────────────────────────────────────────
  /// All ledger entries belonging to [personId], most recent first.
  List<LendedMoney> lendedFor(String personId) =>
      _lended.where((l) => l.personId == personId).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  /// Net balance for a person: positive = they owe the user money,
  /// negative = the user owes them. Only unsettled entries count.
  double personBalance(String personId) => _lended
      .where((l) => l.personId == personId && !l.isSettled)
      .fold(0.0, (sum, l) => sum + (l.type == 'lent' ? l.amount : -l.amount));

  bool personHasOverdue(String personId) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _lended.any((l) =>
        l.personId == personId &&
        !l.isSettled &&
        l.dueDate != null &&
        l.dueDate!.isBefore(today));
  }

  /// Unsettled lent money records expected to be repaid on [day].
  List<LendedMoney> lendedDueOnDay(DateTime day) {
    return _lended.where((m) =>
        !m.isSettled &&
        m.dueDate != null &&
        m.dueDate!.year == day.year &&
        m.dueDate!.month == day.month &&
        m.dueDate!.day == day.day).toList();
  }

  LendedPerson? personById(String id) =>
      _lendedPeople.where((p) => p.id == id).firstOrNull;

  /// The signed balance effect of a lended entry on its linked account:
  /// lending money out decreases the account, borrowing increases it.
  /// Settled entries have no effect.
  double _lendedBalanceEffect(LendedMoney entry) {
    if (entry.isSettled) return 0.0;
    return entry.type == 'lent' ? -entry.amount : entry.amount;
  }

  /// Generates a new UUID for a new person / lended entry.
  String newId() => _uuid.v4();
}
