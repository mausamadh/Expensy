// lib/services/backup_builder.dart
//
// Backward-compatibility shim. The implementation now lives in the
// application layer (hexagonal architecture, HEXAGONAL_MIGRATION_PLAN.md §5
// Phase 5). Existing importers (tests, auto_backup_service) keep working
// unchanged via the static `BackupBuilder.build` API.

import 'package:finwick/adapters/backup/drift_backup_data_repository.dart';
import 'package:finwick/adapters/time/system_clock.dart';
import 'package:finwick/application/backup/backup_use_cases.dart';
import 'package:finwick/domain/backup/backup_artifact.dart';

export 'package:finwick/domain/backup/backup_artifact.dart' show BackupArtifact;

class BackupBuilder {
  static Future<BackupArtifact> build({
    required Map<String, dynamic> settingsJson,
    String? password,
    String namePrefix = 'expensy_backup',
    DateTime? now,
  }) {
    final useCase = CreateBackup(
      data: const DriftBackupDataRepository(),
      clock: const SystemClock(),
    );
    return useCase(
      settingsJson: settingsJson,
      password: password,
      namePrefix: namePrefix,
      now: now,
    );
  }
}
