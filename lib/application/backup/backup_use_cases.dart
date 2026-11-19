// lib/application/backup/backup_use_cases.dart
//
// Application-layer use cases for the Backup bounded context (hexagonal
// architecture, HEXAGONAL_MIGRATION_PLAN.md §5 Phase 5).
//
// Each use case performs the dataset read/write through the
// [BackupDataRepository] port and the pre-restore safety snapshot through the
// [SafetySnapshotStore] port. The provider keeps the in-memory sync and side
// effects (notifications, widgets, net-worth snapshot) under its own mutex.
//
// No Flutter, Drift, or plugin imports (enforced by ci_guard).

import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';

import 'package:finwick/domain/backup/backup_artifact.dart';
import 'package:finwick/domain/backup/backup_encryption_service.dart';
import 'package:finwick/domain/backup/backup_validator.dart';
import 'package:finwick/domain/backup/entity_group_tables.dart';
import 'package:finwick/domain/backup/ports/backup_data_repository.dart';
import 'package:finwick/domain/backup/ports/safety_snapshot_store.dart';
import 'package:finwick/domain/backup/restore_result.dart';
import 'package:finwick/domain/shared/clock.dart';

/// Builds a full backup artifact from the current dataset.
class CreateBackup {
  CreateBackup({
    required BackupDataRepository data,
    required Clock clock,
  })  : _data = data,
        _clock = clock;

  final BackupDataRepository _data;
  final Clock _clock;

  Future<BackupArtifact> call({
    required Map<String, dynamic> settingsJson,
    String? password,
    String namePrefix = 'expensy_backup',
    DateTime? now,
  }) async {
    final dt = now ?? _clock.now();
    final timestamp = DateFormat('yyyyMMdd_HHmmss', 'en_US').format(dt);
    final data = await _data.exportAll();
    data['settings'] = settingsJson;
    data['exported_at'] = dt.toIso8601String();

    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

    if (password != null && password.isNotEmpty) {
      final encryptedBytes = await BackupEncryptionService.encrypt(
        jsonStr: jsonStr,
        password: password,
      );
      return BackupArtifact(
        bytes: encryptedBytes,
        fileName: '${namePrefix}_$timestamp.enc',
        mimeType: 'application/octet-stream',
      );
    } else {
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));
      return BackupArtifact(
        bytes: bytes,
        fileName: '${namePrefix}_$timestamp.json',
        mimeType: 'application/json',
      );
    }
  }
}

/// Builds a selective backup artifact covering only [groups].
class CreateSelectiveBackup {
  CreateSelectiveBackup({
    required BackupDataRepository data,
    required Clock clock,
  })  : _data = data,
        _clock = clock;

  final BackupDataRepository _data;
  final Clock _clock;

  Future<BackupArtifact> call(
    Set<String> groups, {
    DateTime? now,
  }) async {
    final dt = now ?? _clock.now();
    final timestamp = DateFormat('yyyyMMdd_HHmmss', 'en_US').format(dt);
    final tables = tablesForGroups(groups);
    final data = await _data.exportSelective(tables);
    data['exported_at'] = dt.toIso8601String();

    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    final bytes = Uint8List.fromList(utf8.encode(jsonStr));

    return BackupArtifact(
      bytes: bytes,
      fileName: 'expensy_selective_backup_$timestamp.json',
      mimeType: 'application/json',
    );
  }
}

/// Restores a full backup: validates, writes a safety snapshot, then imports
/// the entire dataset. Returns the backup's schema version and raw settings.
class RestoreBackup {
  RestoreBackup({
    required BackupDataRepository data,
    required BackupValidator validator,
    required SafetySnapshotStore snapshots,
    required Clock clock,
  })  : _data = data,
        _validator = validator,
        _snapshots = snapshots,
        _clock = clock;

  final BackupDataRepository _data;
  final BackupValidator _validator;
  final SafetySnapshotStore _snapshots;
  final Clock _clock;

  Future<RestoreResult> call(Map<String, dynamic> data) async {
    if (data['selective'] == true) {
      throw const FormatException(
        'Cannot perform Full Restore on a selective backup. Please use Selective Restore instead.',
      );
    }
    final preview = _validator.validate(data);
    if (!preview.isValid) {
      throw FormatException(
        preview.errorMessage ?? 'Invalid backup file: schema incompatible.',
      );
    }

    final snapshotJson = jsonEncode(await _data.exportAll());
    final snapshotPath = await _snapshots.writeSnapshot(snapshotJson, _clock.now());
    await _data.importAll(data);

    return RestoreResult(
      version: (data['_originalVersion'] as int?) ??
          (data['version'] as int?) ??
          1,
      settingsJson: data['settings'] is Map
          ? Map<String, dynamic>.from(data['settings'] as Map)
          : null,
      snapshotPath: snapshotPath,
    );
  }
}

/// Restores a selective backup: validates, writes a safety snapshot, then
/// imports only the tables covered by [groups].
class RestoreSelective {
  RestoreSelective({
    required BackupDataRepository data,
    required BackupValidator validator,
    required SafetySnapshotStore snapshots,
    required Clock clock,
  })  : _data = data,
        _validator = validator,
        _snapshots = snapshots,
        _clock = clock;

  final BackupDataRepository _data;
  final BackupValidator _validator;
  final SafetySnapshotStore _snapshots;
  final Clock _clock;

  Future<RestoreResult> call(Map<String, dynamic> data, Set<String> groups) async {
    final preview = _validator.validate(data);
    if (!preview.isValid) {
      throw FormatException(
        preview.errorMessage ?? 'Invalid backup file: schema incompatible.',
      );
    }

    final snapshotJson = jsonEncode(await _data.exportAll());
    final snapshotPath = await _snapshots.writeSnapshot(snapshotJson, _clock.now());
    await _data.importSelective(data, tablesForGroups(groups));

    return RestoreResult(
      version: (data['_originalVersion'] as int?) ??
          (data['version'] as int?) ??
          1,
      snapshotPath: snapshotPath,
    );
  }
}

/// Writes a pre-restore safety snapshot of the current dataset and returns
/// the path of the written file. Used before any destructive import (full
/// restore, selective restore, or external CSV import).
class CreateSafetySnapshot {
  CreateSafetySnapshot({
    required BackupDataRepository data,
    required SafetySnapshotStore snapshots,
    required Clock clock,
  })  : _data = data,
        _snapshots = snapshots,
        _clock = clock;

  final BackupDataRepository _data;
  final SafetySnapshotStore _snapshots;
  final Clock _clock;

  Future<String> call() async {
    final snapshotJson = jsonEncode(await _data.exportAll());
    return _snapshots.writeSnapshot(snapshotJson, _clock.now());
  }
}

/// Restores the most recent pre-restore safety snapshot. Returns false when
/// there is no snapshot to restore from.
class UndoLastRestore {
  UndoLastRestore({
    required BackupDataRepository data,
    required SafetySnapshotStore snapshots,
  })  : _data = data,
        _snapshots = snapshots;

  final BackupDataRepository _data;
  final SafetySnapshotStore _snapshots;

  Future<bool> call(String? snapshotPath) async {
    if (snapshotPath == null) return false;
    final jsonStr = await _snapshots.readSnapshot(snapshotPath);
    if (jsonStr == null) return false;
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    await _data.importAll(data);
    return true;
  }
}
