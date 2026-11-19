// lib/adapters/wealth/drift_asset_repository.dart
//
// Drift-backed persistence adapter for the Wealth bounded context (Phase 6).
//
// Thin wrapper over the existing AppDatabase asset methods (which delegate to
// [AppDatabase.instance]) — no SQL changes.

import 'package:finwick/database/app_database.dart';
import 'package:finwick/domain/wealth/ports/asset_repository.dart';
import 'package:finwick/models/models.dart';

class DriftAssetRepository implements AssetRepository {
  const DriftAssetRepository();

  @override
  Future<List<AssetItem>> getAll() => AppDatabase.instance.getAssets();

  @override
  Future<void> insert(AssetItem asset) =>
      AppDatabase.instance.insertAsset(asset);

  @override
  Future<void> update(AssetItem asset) =>
      AppDatabase.instance.updateAsset(asset);

  @override
  Future<void> delete(String id) => AppDatabase.instance.deleteAsset(id);
}
