// lib/domain/backup/restore_preview.dart
//
// Value object describing the result of validating a decoded backup payload
// (hexagonal architecture, HEXAGONAL_MIGRATION_PLAN.md §5 Phase 5).
//
// Pure Dart — no Flutter, Drift, or plugin imports (enforced by ci_guard).

/// A report produced by [BackupValidator.validate] summarising a backup
/// payload's validity, table counts, and any referential-integrity warnings.
class RestorePreview {
  final bool isValid;
  final int schemaVersion;
  final bool isSelective;
  final Map<String, int> tableCounts;
  final List<String> warnings;
  final int orphanCount;
  final String? exportedAt;
  final String? errorMessage;

  const RestorePreview({
    required this.isValid,
    required this.schemaVersion,
    required this.isSelective,
    required this.tableCounts,
    required this.warnings,
    required this.orphanCount,
    this.exportedAt,
    this.errorMessage,
  });
}
