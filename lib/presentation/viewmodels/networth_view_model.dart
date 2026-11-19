// lib/presentation/viewmodels/networth_view_model.dart
//
// Presentation-layer view model for the Net Worth bounded context
// (Phase 6, "Slim the provider") — the user's daily net-worth snapshots.
//
// Owns the `netWorthSnapshots` list and the snapshot-recording logic. Each
// snapshot is a point-in-time capture of the user's total accounts, total
// assets, and net worth, persisted through the [NetWorthStore] port and
// serialized through the provider's zone-based mutation mutex so snapshot
// writes stay atomic with the provider's own ledger writes.
//
// The snapshot's derived values (total accounts, total assets, live net
// worth, currency) are read from other bounded contexts (accounts, assets,
// lended, certificates, loans). Those are injected as functions rather than
// a provider reference, keeping this file free of any `providers/` or
// `database/` import:
//   * [totalAccountsValue] — liquid accounts + gold.
//   * [totalAssetsValue]   — assets + lent money + certificates.
//   * [liveNetWorth]       — total assets - total liabilities.
//   * [currency]           — the settings currency.
//   * [newId]              — id generator (shared with the provider).
//   * [serializeMutation]  — the provider's zone-based mutation mutex.
//
// The debounce timer that coalesces rapid snapshot requests stays in the
// provider (a lifecycle concern tied to its `dispose`); the provider calls
// [recordSnapshot] once the debounce fires.
//
// Layering: this file lives in `presentation/` and imports only `domain/`
// and `models/` — never `adapters/` or `database/`. The store is injected
// through the constructor by the composition root.

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'package:finwick/domain/networth/ports/net_worth_store.dart';
import 'package:finwick/models/models.dart';

class NetWorthViewModel extends ChangeNotifier {
  NetWorthViewModel({
    required NetWorthStore store,
    required String Function() newId,
    required double Function() totalAccountsValue,
    required double Function() totalAssetsValue,
    required double Function() liveNetWorth,
    required String Function() currency,
    required Future<T> Function<T>(Future<T> Function()) serializeMutation,
  })  : _store = store,
        _newId = newId,
        _totalAccountsValue = totalAccountsValue,
        _totalAssetsValue = totalAssetsValue,
        _liveNetWorth = liveNetWorth,
        _currency = currency,
        _serializeMutation = serializeMutation;

  final NetWorthStore _store;
  final String Function() _newId;
  final double Function() _totalAccountsValue;
  final double Function() _totalAssetsValue;
  final double Function() _liveNetWorth;
  final String Function() _currency;
  final Future<T> Function<T>(Future<T> Function()) _serializeMutation;

  // ── State ──────────────────────────────────────────────────────────────
  List<NetWorthSnapshot> _snapshots = [];

  /// All net-worth snapshots, ordered by date ascending.
  List<NetWorthSnapshot> get netWorthSnapshots => _snapshots;

  /// Replaces the snapshot list (fresh-list reactivity rule: reassign,
  /// never mutate in place) and notifies listeners.
  set netWorthSnapshots(List<NetWorthSnapshot> next) {
    _snapshots = next;
    notifyListeners();
  }

  // ── Mutations ──────────────────────────────────────────────────────────

  /// Records (or upserts) today's net-worth snapshot. Called by the
  /// provider once its debounce timer fires, and directly on load/restore.
  Future<void> recordSnapshot() async {
    await _serializeMutation(() async {
      try {
        final today = DateFormat('yyyy-MM-dd', 'en_US').format(DateTime.now());
        final existing = await _store.getSnapshotForDate(today);
        final snap = NetWorthSnapshot(
          id: existing?.id ?? _newId(),
          date: today,
          totalAccounts: _totalAccountsValue(),
          totalAssets: _totalAssetsValue(),
          netWorth: _liveNetWorth(),
          currency: _currency(),
        );
        await _store.insertSnapshot(snap);
        final idx = _snapshots.indexWhere((s) => s.date == today);
        final nextSnaps = List<NetWorthSnapshot>.from(_snapshots);
        if (idx != -1) {
          nextSnaps[idx] = snap;
        } else {
          nextSnaps.add(snap);
          nextSnaps.sort((a, b) => a.date.compareTo(b.date));
        }
        netWorthSnapshots = nextSnaps;
      } catch (e) {
        debugPrint('Error recording net worth snapshot: $e');
      }
    });
  }
}
