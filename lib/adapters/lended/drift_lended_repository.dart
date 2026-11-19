// lib/adapters/lended/drift_lended_repository.dart
//
// Drift-backed persistence adapter for the Lended bounded context (Phase 6).
//
// Thin wrapper over the existing AppDatabase lended-people / lended-money
// methods (which delegate to [AppDatabase.instance]) — no SQL changes.

import 'package:finwick/database/app_database.dart';
import 'package:finwick/domain/lended/ports/lended_repository.dart';
import 'package:finwick/models/models.dart';

class DriftLendedRepository implements LendedRepository {
  const DriftLendedRepository();

  // ── Lended people ─────────────────────────────────────────────────────
  @override
  Future<List<LendedPerson>> getLendedPeople() =>
      AppDatabase.instance.getLendedPeople();

  @override
  Future<void> insertLendedPerson(LendedPerson person) =>
      AppDatabase.instance.insertLendedPerson(person);

  @override
  Future<void> updateLendedPerson(LendedPerson person) =>
      AppDatabase.instance.updateLendedPerson(person);

  @override
  Future<void> deleteLendedPerson(String id) =>
      AppDatabase.instance.deleteLendedPerson(id);

  @override
  Future<void> deleteLendedForPerson(String personId) =>
      AppDatabase.instance.deleteLendedForPerson(personId);

  // ── Lended money ──────────────────────────────────────────────────────
  @override
  Future<List<LendedMoney>> getLended() => AppDatabase.instance.getLended();

  @override
  Future<void> insertLended(LendedMoney entry) =>
      AppDatabase.instance.insertLended(entry);

  @override
  Future<void> updateLended(LendedMoney entry) =>
      AppDatabase.instance.updateLended(entry);

  @override
  Future<void> deleteLended(String id) =>
      AppDatabase.instance.deleteLended(id);
}
