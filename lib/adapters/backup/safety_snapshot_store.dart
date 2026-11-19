// lib/adapters/backup/safety_snapshot_store.dart
//
// Filesystem adapter for the pre-restore safety snapshot (Phase 5).
//
// Owns directory resolution (primary DB folder with a system-temp fallback)
// and the retain-last-3 policy. The domain use case only asks for a snapshot
// to be written and read back.

import 'dart:io';

import 'package:finwick/domain/backup/ports/safety_snapshot_store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

class FileSafetySnapshotStore implements SafetySnapshotStore {
  const FileSafetySnapshotStore();

  @override
  Future<String> writeSnapshot(String json, DateTime now) async {
    final ts = now
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final fileName = 'expensy_prerestore_$ts.json';

    Directory? targetDir;
    try {
      final dbFolder = await sqflite.getDatabasesPath();
      final primaryDir = Directory(p.join(dbFolder, 'safety_snapshots'));
      if (!primaryDir.existsSync()) {
        primaryDir.createSync(recursive: true);
      }
      final file = File(p.join(primaryDir.path, fileName));
      await file.writeAsString(json);
      targetDir = primaryDir;
      _retainLast3(targetDir);
      return file.path;
    } catch (primaryErr) {
      try {
        final fallbackDir = Directory(
            p.join(Directory.systemTemp.path, 'expensy_safety_snapshots'));
        if (!fallbackDir.existsSync()) {
          fallbackDir.createSync(recursive: true);
        }
        final file = File(p.join(fallbackDir.path, fileName));
        await file.writeAsString(json);
        targetDir = fallbackDir;
        _retainLast3(targetDir);
        return file.path;
      } catch (fallbackErr) {
        throw StateError(
          'Pre-restore safety snapshot failed ($primaryErr / $fallbackErr). Restore aborted to protect existing data.',
        );
      }
    }
  }

  @override
  Future<String?> readSnapshot(String path) async {
    final file = File(path);
    if (!file.existsSync()) return null;
    return file.readAsString();
  }

  void _retainLast3(Directory dir) {
    try {
      final files = dir.listSync().whereType<File>().toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      if (files.length > 3) {
        for (int i = 3; i < files.length; i++) {
          try {
            files[i].deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
