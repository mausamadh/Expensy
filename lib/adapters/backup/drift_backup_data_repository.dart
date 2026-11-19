// lib/adapters/backup/drift_backup_data_repository.dart
//
// Drift-backed adapter for the Backup bounded context (Phase 5).
//
// Thin wrapper over the existing AppDatabase export/import methods (which
// delegate to [AppDatabase.instance]) — no SQL changes.

import 'package:finwick/database/app_database.dart';
import 'package:finwick/domain/backup/ports/backup_data_repository.dart';

class DriftBackupDataRepository implements BackupDataRepository {
  const DriftBackupDataRepository();

  @override
  Future<Map<String, dynamic>> exportAll() => AppDatabase.instance.exportAll();

  @override
  Future<Map<String, dynamic>> exportSelective(Set<String> tables) =>
      AppDatabase.instance.exportSelective(tables);

  @override
  Future<void> importAll(Map<String, dynamic> data) =>
      AppDatabase.instance.importAll(data);

  @override
  Future<void> importSelective(Map<String, dynamic> data, Set<String> tables) =>
      AppDatabase.instance.importSelective(data, tables);
}
