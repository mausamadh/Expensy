// lib/domain/lended/ports/lended_repository.dart
//
// Domain port for the Lended bounded context (Phase 6) — the people you
// lend/borrow money to (per-person ledger "accounts") and the individual
// lend/borrow entries that form each person's ledger history.
//
// Pure Dart: imports only the shared models. The concrete Drift adapter
// lives in `adapters/` and is injected by the composition root.
//
// Note: the ledger-coupled side effects (reversing unsettled balances on
// delete/settle, net-worth snapshots) are NOT part of this port — they are
// handled by the view model through injected hooks.

import 'package:finwick/models/models.dart';

abstract interface class LendedRepository {
  // ── Lended people ─────────────────────────────────────────────────────
  Future<List<LendedPerson>> getLendedPeople();
  Future<void> insertLendedPerson(LendedPerson person);
  Future<void> updateLendedPerson(LendedPerson person);

  /// Deletes a person and every lended-money entry that belongs to them.
  Future<void> deleteLendedPerson(String id);

  /// Deletes only the lended-money entries for a person (the person row is
  /// kept). Used by the view model so it can reverse balances before the
  /// person row is removed.
  Future<void> deleteLendedForPerson(String personId);

  // ── Lended money (ledger entries) ─────────────────────────────────────
  Future<List<LendedMoney>> getLended();
  Future<void> insertLended(LendedMoney entry);
  Future<void> updateLended(LendedMoney entry);
  Future<void> deleteLended(String id);
}
