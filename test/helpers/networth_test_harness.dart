// test/helpers/networth_test_harness.dart
//
// Shared widget-test harness for the Net Worth view model (Phase 6).
//
// Screens that read the delegated `netWorthSnapshots` collection watch
// `NetWorthViewModel`. Widget tests that mount those screens must therefore
// provide a `NetWorthViewModel` in addition to `AppProvider`. This helper
// builds a VM backed by an in-memory fake store (no DB) and wraps a child in
// a `MultiProvider` exposing both notifiers.

import 'package:finwick/domain/networth/ports/net_worth_store.dart';
import 'package:finwick/models/models.dart';
import 'package:finwick/presentation/viewmodels/networth_view_model.dart';
import 'package:finwick/providers/app_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// In-memory [NetWorthStore] for widget tests — no DB access.
class InMemoryNetWorthStore implements NetWorthStore {
  List<NetWorthSnapshot> _snapshots = [];

  @override
  Future<List<NetWorthSnapshot>> getSnapshots() async =>
      List.unmodifiable(_snapshots);

  @override
  Future<NetWorthSnapshot?> getSnapshotForDate(String date) async {
    for (final s in _snapshots) {
      if (s.date == date) return s;
    }
    return null;
  }

  @override
  Future<void> insertSnapshot(NetWorthSnapshot snap) async {
    final idx = _snapshots.indexWhere((s) => s.date == snap.date);
    if (idx != -1) {
      _snapshots = [
        for (final s in _snapshots) s.date == snap.date ? snap : s,
      ];
    } else {
      _snapshots = [..._snapshots, snap]
        ..sort((a, b) => a.date.compareTo(b.date));
    }
  }
}

/// Builds a [NetWorthViewModel] backed by an in-memory fake store.
///
/// The cross-cutting hooks are no-ops in tests (no DB, no derived totals),
/// so snapshot recording runs against the in-memory store only.
NetWorthViewModel buildNetWorthViewModel() => NetWorthViewModel(
      store: InMemoryNetWorthStore(),
      newId: () => 'snap-test-id',
      totalAccountsValue: () => 0.0,
      totalAssetsValue: () => 0.0,
      liveNetWorth: () => 0.0,
      currency: () => 'USD',
      serializeMutation: <T>(Future<T> Function() action) => action(),
    );

/// Wraps [child] in a `MultiProvider` exposing [app] and a fresh
/// [NetWorthViewModel], so screens that watch the net-worth view model
/// (e.g. the net-worth and insights screens) resolve it in tests.
///
/// The view model is wired into [app] first, so data assigned through the
/// provider's delegating setter (`app.netWorthSnapshots = ...`) lands in the
/// view model and its listeners fire.
Widget wrapWithNetWorth(AppProvider app, Widget child) {
  final vm = buildNetWorthViewModel();
  app.wireNetWorthVm(vm);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppProvider>.value(value: app),
      ChangeNotifierProvider<NetWorthViewModel>.value(value: vm),
    ],
    child: child,
  );
}
