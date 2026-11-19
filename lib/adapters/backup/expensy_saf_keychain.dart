// lib/adapters/backup/expensy_saf_keychain.dart
//
// SAF-backed adapter for the auto-backup encryption password (Phase 5).
//
// Thin wrapper over the [ExpensySaf] secret-store statics.

import 'package:expensy_saf/expensy_saf.dart';
import 'package:finwick/domain/backup/ports/keychain.dart';

class ExpensySafKeychain implements Keychain {
  const ExpensySafKeychain();

  @override
  Future<bool> setSecret(String key, String value) =>
      ExpensySaf.setSecret(key, value);

  @override
  Future<String?> getSecret(String key) => ExpensySaf.getSecret(key);

  @override
  Future<void> clearSecret(String key) => ExpensySaf.clearSecret(key);
}
