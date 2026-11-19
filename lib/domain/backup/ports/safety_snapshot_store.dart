// lib/domain/backup/ports/safety_snapshot_store.dart
//
// Port for the pre-restore safety snapshot (hexagonal architecture,
// HEXAGONAL_MIGRATION_PLAN.md §5 Phase 5).
//
// Pure Dart — no Flutter, Drift, or plugin imports (enforced by ci_guard).
// The concrete adapter owns directory resolution (primary DB folder with a
// system-temp fallback) and the retain-last-3 policy.

/// Persists and reads the pre-restore safety snapshot that protects existing
/// data before a restore wipes the database.
abstract interface class SafetySnapshotStore {
  /// Writes [json] (a full dataset export) as a pre-restore snapshot and
  /// returns the absolute path of the written file.
  ///
  /// Retains only the most recent 3 snapshots. Throws a [StateError] if the
  /// snapshot cannot be written to any location.
  Future<String> writeSnapshot(String json, DateTime now);

  /// Returns the JSON string stored at [path], or null if the file no longer
  /// exists.
  Future<String?> readSnapshot(String path);
}
