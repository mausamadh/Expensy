// lib/domain/networth/ports/net_worth_store.dart
//
// Domain port for the Net Worth bounded context (Phase 6, "Slim the
// provider"). The [NetWorthViewModel] persists daily net-worth snapshots
// through this port; the concrete Drift implementation lives in
// `adapters/` and is injected by the composition root.
//
// Layering: this file lives in `domain/` and imports only `models/` —
// never `database/`, `adapters/`, or `providers/`.

import 'package:finwick/models/models.dart';

abstract class NetWorthStore {
  /// All net-worth snapshots, ordered by date ascending.
  Future<List<NetWorthSnapshot>> getSnapshots();

  /// The snapshot recorded for [date] (`yyyy-MM-dd`), or null if none.
  Future<NetWorthSnapshot?> getSnapshotForDate(String date);

  /// Inserts (or upserts, by id) a snapshot.
  Future<void> insertSnapshot(NetWorthSnapshot snap);
}
