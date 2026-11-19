// lib/domain/backup/backup_payload_parser.dart
//
// Pure parser for raw backup bytes (hexagonal architecture,
// HEXAGONAL_MIGRATION_PLAN.md §5 Phase 5).
//
// Pure Dart — no Flutter, Drift, or plugin imports (enforced by ci_guard).
// Decryption uses the domain [BackupEncryptionService]; the application layer
// (and the provider) call this to turn raw file bytes into a decoded map.

import 'dart:convert';

import 'backup_encryption_service.dart';

/// Decodes (and, when needed, decrypts) raw backup bytes into a map.
///
/// Throws [FormatException] with the message `'NEEDS_PASSWORD'` when the
/// payload is encrypted and no password is supplied, and with descriptive
/// messages for non-JSON or unrecognisable payloads.
class BackupPayloadParser {
  const BackupPayloadParser();

  /// The top-level keys that identify a payload as a Finwick backup.
  static const Set<String> knownKeys = {
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
    'certificates',
    'net_worth_snapshots',
    'version',
    'settings',
    'savings_goals',
    'savings_contributions',
    'loans',
    'loan_payments',
    'transaction_presets',
    'transaction_splits',
    'selective',
  };

  Future<Map<String, dynamic>> parse(
    List<int> bytes, {
    String? password,
    String? extension,
  }) async {
    final ext = extension?.toLowerCase();
    String jsonStr;
    if (BackupEncryptionService.isEncrypted(bytes) || ext == 'enc') {
      if (password == null || password.isEmpty) {
        throw const FormatException('NEEDS_PASSWORD');
      }
      jsonStr = await BackupEncryptionService.decrypt(
        bytes: bytes,
        password: password,
      );
    } else {
      try {
        jsonStr = utf8.decode(bytes);
      } catch (_) {
        throw const FormatException(
          'Please select a valid .json or .enc Finwick backup file.',
        );
      }
    }

    final dynamic decoded = jsonDecode(jsonStr);
    if (decoded is! Map) {
      throw const FormatException(
        'Invalid backup file: top-level value is not a JSON object.',
      );
    }
    final data = Map<String, dynamic>.from(decoded);

    if (!data.keys.any(knownKeys.contains)) {
      throw const FormatException(
        'Invalid backup file: no recognisable Finwick data found.',
      );
    }
    return data;
  }
}
