// lib/presentation/viewmodels/presets_view_model.dart
//
// Presentation-layer view model for transaction presets (1-tap quick-log
// templates) — HEXAGONAL_MIGRATION_PLAN.md Phase 6 ("Slim the provider").
//
// Owns the preset state slice (the `presets` list) and delegates every
// mutation to the [PresetRepository] port. Replaces the preset CRUD slice of
// `AppProvider`.
//
// Note: `logPreset` (1-tap logging a preset as a transaction/transfer) stays
// on `AppProvider` because it is a ledger operation that depends on the
// account/transaction write path; it takes a preset as a parameter and does
// not read this list.
//
// Layering: this file lives in `presentation/` and imports only `domain/`
// and `models/` — never `adapters/` or `database/`. The repository is
// injected through the constructor by the composition root.
import 'package:flutter/foundation.dart';

import 'package:finwick/domain/ledger/ports/preset_repository.dart';
import 'package:finwick/domain/shared/uuid.dart';
import 'package:finwick/models/models.dart';

class PresetsViewModel extends ChangeNotifier {
  PresetsViewModel({required PresetRepository repository})
      : _repo = repository,
        _uuid = Uuid();

  final PresetRepository _repo;
  final Uuid _uuid;

  // ── State ──────────────────────────────────────────────────────────────
  List<TransactionPreset> _presets = [];

  /// All presets in creation order.
  List<TransactionPreset> get presets => _presets;

  /// Replaces the preset list (fresh-list reactivity rule: reassign, never
  /// mutate in place) and notifies listeners.
  set presets(List<TransactionPreset> next) {
    _presets = next;
    notifyListeners();
  }

  // ── Mutations ──────────────────────────────────────────────────────────
  Future<void> addPreset(TransactionPreset preset) async {
    await _repo.insert(preset);
    _presets = await _repo.getAll();
    notifyListeners();
  }

  Future<void> updatePreset(TransactionPreset preset) async {
    await _repo.update(preset);
    _presets = await _repo.getAll();
    notifyListeners();
  }

  Future<void> deletePreset(String id) async {
    await _repo.delete(id);
    _presets = await _repo.getAll();
    notifyListeners();
  }

  /// Generates a new UUID for a new preset.
  String newId() => _uuid.v4();
}
