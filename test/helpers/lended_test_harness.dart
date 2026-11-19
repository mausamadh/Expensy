// test/helpers/lended_test_harness.dart
//
// Shared widget-test harness for the Lended view model (Phase 6).
//
// `MainShell` eagerly builds its tabs (Transactions, More) via an
// IndexedStack, and those screens read the delegated `lendedPeople` /
// `lended` collections through `LendedViewModel`. Widget tests that mount
// `MainShell` (or the lended screens directly) must therefore provide a
// `LendedViewModel` in addition to `AppProvider`. This helper builds a VM
// backed by an in-memory fake repository (no DB) and wraps a child in a
// `MultiProvider` exposing both notifiers.

import 'package:finwick/domain/lended/ports/lended_repository.dart';
import 'package:finwick/models/models.dart';
import 'package:finwick/presentation/viewmodels/lended_view_model.dart';
import 'package:finwick/providers/app_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// In-memory [LendedRepository] for widget tests — no DB access.
class InMemoryLendedRepository implements LendedRepository {
  List<LendedPerson> _people = [];
  List<LendedMoney> _lended = [];

  @override
  Future<List<LendedPerson>> getLendedPeople() async =>
      List.unmodifiable(_people);

  @override
  Future<void> insertLendedPerson(LendedPerson person) async {
    _people = [..._people, person];
  }

  @override
  Future<void> updateLendedPerson(LendedPerson person) async {
    _people = [
      for (final p in _people) p.id == person.id ? person : p,
    ];
  }

  @override
  Future<void> deleteLendedPerson(String id) async {
    _people = [for (final p in _people) if (p.id != id) p];
    _lended = [for (final l in _lended) if (l.personId != id) l];
  }

  @override
  Future<void> deleteLendedForPerson(String personId) async {
    _lended = [for (final l in _lended) if (l.personId != personId) l];
  }

  @override
  Future<List<LendedMoney>> getLended() async =>
      List.unmodifiable(_lended);

  @override
  Future<void> insertLended(LendedMoney entry) async {
    _lended = [entry, ..._lended];
  }

  @override
  Future<void> updateLended(LendedMoney entry) async {
    _lended = [
      for (final l in _lended) l.id == entry.id ? entry : l,
    ];
  }

  @override
  Future<void> deleteLended(String id) async {
    _lended = [for (final l in _lended) if (l.id != id) l];
  }
}

/// Builds a [LendedViewModel] backed by an in-memory fake repository.
///
/// The cross-cutting hooks are no-ops in tests (no DB, no net-worth
/// snapshots, no notifications), so lended mutations run against the
/// in-memory repository only.
LendedViewModel buildLendedViewModel() => LendedViewModel(
      repository: InMemoryLendedRepository(),
      applyBalanceDelta: (accountId, delta) async {},
      balanceAccountIdFor: (accountId) => accountId,
      refreshAccounts: () async {},
      onNetWorthChanged: () async {},
      personName: (id) => null,
      currency: () => 'NPR',
      serializeMutation: <T>(Future<T> Function() action) => action(),
    );

/// Wraps [child] in a `MultiProvider` exposing [app] and a fresh
/// [LendedViewModel], so screens that watch the lended view model (e.g. the
/// Transactions/More tabs inside `MainShell`, or the lended screens
/// directly) resolve it in tests.
///
/// The view model is wired into [app] first, so data assigned through the
/// provider's delegating setters (`app.lended = ...`) lands in the view
/// model and its listeners fire.
Widget wrapWithLended(AppProvider app, Widget child) {
  final vm = buildLendedViewModel();
  app.wireLendedVm(vm);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppProvider>.value(value: app),
      ChangeNotifierProvider<LendedViewModel>.value(value: vm),
    ],
    child: child,
  );
}
