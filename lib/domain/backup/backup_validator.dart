// lib/domain/backup/backup_validator.dart
//
// Pure referential-integrity validator for decoded backup payloads
// (hexagonal architecture, HEXAGONAL_MIGRATION_PLAN.md §5 Phase 5).
//
// Pure Dart — no Flutter, Drift, or plugin imports (enforced by ci_guard).
// The schema version is injected rather than imported from the database
// layer, keeping the domain free of adapter dependencies.

import 'restore_preview.dart';

/// Inspects a raw decoded backup map and produces a [RestorePreview] report.
///
/// The current schema version is injected via the constructor so the domain
/// never depends on the Drift database layer.
class BackupValidator {
  final int currentSchemaVersion;

  const BackupValidator({required this.currentSchemaVersion});

  /// The set of tables a full backup may contain.
  static const Set<String> knownTables = {
    'accounts',
    'categories',
    'transactions',
    'recurring_payments',
    'wishlist',
    'lended_people',
    'lended_money',
    'assets',
    'budgets',
    'recurring_history',
    'savings_goals',
    'savings_contributions',
    'loans',
    'loan_payments',
    'transaction_presets',
    'transaction_splits',
    'certificates',
    'net_worth_snapshots',
    'sms_sender_account_mappings',
  };

  /// Inspects a raw decoded backup map and returns a [RestorePreview] report.
  RestorePreview validate(Map<String, dynamic> data) {
    final version = (data['version'] as num?)?.toInt() ?? 1;
    if (version > currentSchemaVersion) {
      return RestorePreview(
        isValid: false,
        schemaVersion: version,
        isSelective: false,
        tableCounts: {},
        warnings: [],
        orphanCount: 0,
        errorMessage:
            'Backup version $version is newer than current app version ($currentSchemaVersion).',
      );
    }

    final isSelective = data['selective'] == true;
    final exportedAt = data['exported_at'] as String?;
    final tableCounts = <String, int>{};
    final warnings = <String>[];
    int orphanCount = 0;

    for (final table in knownTables) {
      if (data.containsKey(table) && data[table] is List) {
        final list = data[table] as List;
        tableCounts[table] = list.length;
      }
    }

    // Check orphan recurring history
    if (data.containsKey('recurring_history') &&
        data.containsKey('recurring_payments')) {
      final recIds = (data['recurring_payments'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((r) => r['id'] as String?)
              .whereType<String>()
              .toSet() ??
          <String>{};
      final history = (data['recurring_history'] as List?)
              ?.whereType<Map<String, dynamic>>() ??
          [];
      for (final h in history) {
        final recId = h['recurring_id'] as String?;
        if (recId != null && !recIds.contains(recId)) {
          orphanCount++;
        }
      }
      if (orphanCount > 0) {
        warnings.add(
            'Found $orphanCount recurring history records without a parent recurring payment.');
      }
    }

    // Check account references in transactions, recurring_payments, and
    // transaction_presets
    if (data.containsKey('accounts')) {
      final accIds = (data['accounts'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((a) => a['id'] as String?)
              .whereType<String>()
              .toSet() ??
          <String>{};
      if (data.containsKey('transactions')) {
        final txs = (data['transactions'] as List?)
                ?.whereType<Map<String, dynamic>>() ??
            [];
        int missingAccTxs = 0;
        for (final t in txs) {
          final accId = t['account_id'] as String?;
          if (accId != null && !accIds.contains(accId)) {
            missingAccTxs++;
          }
        }
        if (missingAccTxs > 0) {
          warnings.add(
              '$missingAccTxs transactions reference accounts not in this backup.');
        }
      }

      if (data.containsKey('recurring_payments')) {
        final recs = (data['recurring_payments'] as List?)
                ?.whereType<Map<String, dynamic>>() ??
            [];
        int missingRecAcc = 0;
        for (final r in recs) {
          final accId = r['account_id'] as String?;
          final toAccId = r['to_account_id'] as String?;
          if ((accId != null && accId.isNotEmpty && !accIds.contains(accId)) ||
              (toAccId != null &&
                  toAccId.isNotEmpty &&
                  !accIds.contains(toAccId))) {
            missingRecAcc++;
          }
        }
        if (missingRecAcc > 0) {
          warnings.add(
              '$missingRecAcc recurring rules reference accounts not in this backup.');
        }
      }

      if (data.containsKey('transaction_presets')) {
        final presets = (data['transaction_presets'] as List?)
                ?.whereType<Map<String, dynamic>>() ??
            [];
        int missingPresetAcc = 0;
        for (final p in presets) {
          final accId = p['account_id'] as String?;
          final toAccId = p['to_account_id'] as String?;
          if ((accId != null && accId.isNotEmpty && !accIds.contains(accId)) ||
              (toAccId != null &&
                  toAccId.isNotEmpty &&
                  !accIds.contains(toAccId))) {
            missingPresetAcc++;
          }
        }
        if (missingPresetAcc > 0) {
          warnings.add(
              '$missingPresetAcc presets reference accounts not in this backup.');
        }
      }
    }

    // Check subcategory parent references
    if (data.containsKey('categories')) {
      final cats = (data['categories'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          [];
      final catIds =
          cats.map((c) => c['id'] as String?).whereType<String>().toSet();
      int orphanSubs = 0;
      for (final c in cats) {
        final pid = c['parent_id'] as String?;
        if (pid != null && pid.isNotEmpty && !catIds.contains(pid)) {
          orphanSubs++;
        }
      }
      if (orphanSubs > 0) {
        warnings.add(
            '$orphanSubs subcategories reference a missing parent category and will be promoted on restore.');
      }
    }

    return RestorePreview(
      isValid: true,
      schemaVersion: version,
      isSelective: isSelective,
      tableCounts: tableCounts,
      warnings: warnings,
      orphanCount: orphanCount,
      exportedAt: exportedAt,
    );
  }
}
