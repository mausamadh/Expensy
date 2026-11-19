// lib/domain/backup/restore_result.dart
//
// Value object returned by the restore use cases (hexagonal architecture,
// HEXAGONAL_MIGRATION_PLAN.md §5 Phase 5).
//
// Pure Dart — no Flutter, Drift, or plugin imports (enforced by ci_guard).

/// The outcome of a successful restore: the schema version the backup was
/// written with, the raw settings map (if the backup carried one), and the
/// path of the pre-restore safety snapshot that was written.
///
/// The settings map is returned raw (not parsed into the app's settings type)
/// so the domain stays free of the presentation-layer settings model.
class RestoreResult {
  final int version;
  final Map<String, dynamic>? settingsJson;
  final String? snapshotPath;

  const RestoreResult({
    required this.version,
    this.settingsJson,
    this.snapshotPath,
  });
}
