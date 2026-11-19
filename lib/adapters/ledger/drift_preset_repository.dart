// lib/adapters/ledger/drift_preset_repository.dart
//
// Drift-backed persistence adapter for transaction presets (Phase 6).
//
// Thin wrapper over the existing AppDatabase preset methods (which delegate
// to [AppDatabase.instance]) — no SQL changes.

import 'package:finwick/database/app_database.dart';
import 'package:finwick/domain/ledger/ports/preset_repository.dart';
import 'package:finwick/models/models.dart';

class DriftPresetRepository implements PresetRepository {
  const DriftPresetRepository();

  @override
  Future<List<TransactionPreset>> getAll() =>
      AppDatabase.instance.getPresets();

  @override
  Future<void> insert(TransactionPreset preset) =>
      AppDatabase.instance.insertPreset(preset);

  @override
  Future<void> update(TransactionPreset preset) =>
      AppDatabase.instance.updatePreset(preset);

  @override
  Future<void> delete(String id) => AppDatabase.instance.deletePreset(id);
}
