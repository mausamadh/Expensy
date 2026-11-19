// lib/domain/backup/ports/backup_data_repository.dart
//
// Port for reading/writing the full application dataset used by backup and
// restore (hexagonal architecture, HEXAGONAL_MIGRATION_PLAN.md §5 Phase 5).
//
// Pure Dart — no Flutter, Drift, or plugin imports (enforced by ci_guard).
// The concrete adapter wraps the existing Drift database export/import.

/// Reads and writes the application dataset as plain JSON maps.
///
/// A "full" export/import touches every table; a "selective" one is scoped to
/// an explicit set of table names.
abstract interface class BackupDataRepository {
  /// Exports every table into a single map keyed by table name.
  Future<Map<String, dynamic>> exportAll();

  /// Exports only the given [tables] into a single map.
  Future<Map<String, dynamic>> exportSelective(Set<String> tables);

  /// Replaces the entire database contents with [data].
  Future<void> importAll(Map<String, dynamic> data);

  /// Replaces only the [tables] present in [data].
  Future<void> importSelective(Map<String, dynamic> data, Set<String> tables);
}
