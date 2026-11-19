// lib/domain/ledger/ports/preset_repository.dart
//
// Persistence port for transaction presets (hexagonal architecture,
// HEXAGONAL_MIGRATION_PLAN.md Phase 6 — "Slim the provider").
//
// Domain-owned interface: the presentation-layer PresetsViewModel programs
// against this, and a Drift adapter (lib/adapters/ledger/) provides the
// concrete implementation over the existing AppDatabase. No Flutter, Drift,
// or plugin imports here (enforced by ci_guard).

import 'package:finwick/models/models.dart';

/// Read/write access to transaction presets (1-tap quick-log templates).
abstract interface class PresetRepository {
  /// All presets in creation order.
  Future<List<TransactionPreset>> getAll();

  /// Inserts a new preset.
  Future<void> insert(TransactionPreset preset);

  /// Replaces an existing preset (matched by id).
  Future<void> update(TransactionPreset preset);

  /// Deletes the preset with [id].
  Future<void> delete(String id);
}
