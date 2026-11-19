// lib/adapters/backup/drift_backup_data_repository.dart
//
// Drift-backed adapter for the Backup bounded context (Phase 5).
//
// Thin wrapper over the existing [DBHelper] export/import statics (which
// delegate to [AppDatabase.instance]) — no SQL changes.

import 'package:finwick/database/db_helper.dart';
import 'package:finwick/domain/backup/ports/backup_data_repository.dart';

class DriftBackupDataRepository implements BackupDataRepository {
  const DriftBackupDataRepository();

  @override
  Future<Map<String, dynamic>> exportAll() => DBHelper.exportAll();

  @override
  Future<Map<String, dynamic>> exportSelective(Set<String> tables) =>
      DBHelper.exportSelective(tables);

  @override
  Future<void> importAll(Map<String, dynamic> data) =>
      DBHelper.importAll(data);

  @override
  Future<void> importSelective(Map<String, dynamic> data, Set<String> tables) =>
      DBHelper.importSelective(data, tables);
}
