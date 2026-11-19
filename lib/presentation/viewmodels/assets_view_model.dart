// lib/presentation/viewmodels/assets_view_model.dart
//
// Presentation-layer view model for the Assets (valuables) screen
// (HEXAGONAL_MIGRATION_PLAN.md Phase 6 — "Slim the provider").
//
// Owns the asset state slice (the `assets` list + `totalAssetsValue`) and
// delegates every mutation to the [AssetRepository] port. Replaces the asset
// slice of `AppProvider`.
//
// Cross-cutting couplings are injected as functions rather than a provider
// reference, keeping this file free of any `providers/` import:
//   * [convertToMain] — FX conversion (provider's `convertToMain` tear-off),
//     used by [totalAssetsValue].
//   * [onNetWorthChanged] — net-worth snapshot hook (provider's
//     `recordNetWorthSnapshot` tear-off), fired after every mutation.
//
// Layering: this file lives in `presentation/` and imports only `domain/`
// and `models/` — never `adapters/` or `database/`. The repository is
// injected through the constructor by the composition root.
import 'package:flutter/foundation.dart';

import 'package:finwick/domain/shared/uuid.dart';
import 'package:finwick/domain/wealth/ports/asset_repository.dart';
import 'package:finwick/models/models.dart';

/// Converts an amount in [fromCurrency] to the main currency.
typedef ConvertToMain = double Function(double amount, String fromCurrency);

class AssetsViewModel extends ChangeNotifier {
  AssetsViewModel({
    required AssetRepository repository,
    required ConvertToMain convertToMain,
    required Future<void> Function() onNetWorthChanged,
  })  : _repo = repository,
        _convertToMain = convertToMain,
        _onNetWorthChanged = onNetWorthChanged,
        _uuid = Uuid();

  final AssetRepository _repo;
  final ConvertToMain _convertToMain;
  final Future<void> Function() _onNetWorthChanged;
  final Uuid _uuid;

  // ── State ──────────────────────────────────────────────────────────────
  List<AssetItem> _assets = [];

  /// All assets in creation order.
  List<AssetItem> get assets => _assets;

  /// Replaces the asset list (fresh-list reactivity rule: reassign, never
  /// mutate in place) and notifies listeners.
  set assets(List<AssetItem> next) {
    _assets = next;
    notifyListeners();
  }

  /// Total asset value converted to the main currency.
  ///
  /// [convertToMain] already short-circuits when the asset currency equals
  /// the main currency or when no rates are loaded, so every asset can be
  /// routed through it.
  double get totalAssetsValue =>
      _assets.fold(0.0, (sum, a) => sum + _convertToMain(a.value, a.currency));

  // ── Mutations ──────────────────────────────────────────────────────────
  Future<void> addAsset(AssetItem asset) async {
    await _repo.insert(asset);
    _assets = await _repo.getAll();
    notifyListeners();
    await _onNetWorthChanged();
  }

  Future<void> updateAsset(AssetItem asset) async {
    await _repo.update(asset);
    _assets = await _repo.getAll();
    notifyListeners();
    await _onNetWorthChanged();
  }

  Future<void> deleteAsset(String id) async {
    await _repo.delete(id);
    _assets = await _repo.getAll();
    notifyListeners();
    await _onNetWorthChanged();
  }

  /// Deletes [id] and returns an undo callback that re-inserts the asset.
  Future<VoidCallback> deleteAssetWithUndo(String id) async {
    final asset = _assets.firstWhere((a) => a.id == id);
    await deleteAsset(id);
    return () async {
      await _repo.insert(asset);
      _assets = await _repo.getAll();
      notifyListeners();
      await _onNetWorthChanged();
    };
  }

  /// Notifies listeners that FX rates changed so converted values recompute.
  void onRatesChanged() => notifyListeners();

  /// Generates a new UUID for a new asset.
  String newId() => _uuid.v4();
}
