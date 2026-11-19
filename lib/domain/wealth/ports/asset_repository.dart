// lib/domain/wealth/ports/asset_repository.dart
//
// Persistence port for the Wealth bounded context (hexagonal architecture,
// HEXAGONAL_MIGRATION_PLAN.md Phase 6 — "Slim the provider").
//
// Domain-owned interface: the presentation-layer AssetsViewModel programs
// against this, and a Drift adapter (lib/adapters/wealth/) provides the
// concrete implementation over the existing AppDatabase. No Flutter, Drift,
// or plugin imports here (enforced by ci_guard).

import 'package:finwick/models/models.dart';

/// Read/write access to asset (valuables) entries.
abstract interface class AssetRepository {
  /// All assets in creation order.
  Future<List<AssetItem>> getAll();

  /// Inserts a new asset.
  Future<void> insert(AssetItem asset);

  /// Replaces an existing asset (matched by id).
  Future<void> update(AssetItem asset);

  /// Deletes the asset with [id].
  Future<void> delete(String id);
}
