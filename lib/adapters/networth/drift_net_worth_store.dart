// lib/adapters/networth/drift_net_worth_store.dart
//
// Drift-backed read+write adapter for the Net Worth bounded context
// (Phase 6). Thin wrapper over the existing AppDatabase methods — no SQL
// changes.

import 'package:finwick/database/app_database.dart';
import 'package:finwick/domain/networth/ports/net_worth_store.dart';
import 'package:finwick/models/models.dart';

class DriftNetWorthStore implements NetWorthStore {
  const DriftNetWorthStore();

  @override
  Future<List<NetWorthSnapshot>> getSnapshots() =>
      AppDatabase.instance.getNetWorthSnapshots();

  @override
  Future<NetWorthSnapshot?> getSnapshotForDate(String date) =>
      AppDatabase.instance.getNetWorthSnapshotForDate(date);

  @override
  Future<void> insertSnapshot(NetWorthSnapshot snap) =>
      AppDatabase.instance.insertNetWorthSnapshot(snap);
}
