// lib/services/backup_validator.dart
//
// Backward-compatibility shim. The implementation now lives in the domain
// layer (hexagonal architecture, HEXAGONAL_MIGRATION_PLAN.md §5 Phase 5).
//
// Existing importers (tests, provider) use the static API
// (`BackupValidator.validate`, `BackupValidator.currentSchemaVersion`,
// `BackupValidator.knownTables`) and the `RestorePreview` type, all of which
// are preserved here by delegating to a domain instance.

import 'package:finwick/domain/backup/backup_validator.dart' as domain;
import 'package:finwick/domain/backup/restore_preview.dart';

import '../database/app_database.dart';

export 'package:finwick/domain/backup/restore_preview.dart' show RestorePreview;

class BackupValidator {
  static const int currentSchemaVersion = AppDatabase.currentSchemaVersion;

  static const Set<String> knownTables = domain.BackupValidator.knownTables;

  static final domain.BackupValidator _instance =
      domain.BackupValidator(currentSchemaVersion: currentSchemaVersion);

  /// Inspects a raw decoded backup map and returns a [RestorePreview] report.
  static RestorePreview validate(Map<String, dynamic> data) =>
      _instance.validate(data);
}
