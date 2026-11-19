// lib/domain/backup/ports/keychain.dart
//
// Port for storing the auto-backup encryption password (hexagonal
// architecture, HEXAGONAL_MIGRATION_PLAN.md §5 Phase 5).
//
// Pure Dart — no Flutter, Drift, or plugin imports (enforced by ci_guard).
// The concrete adapter wraps the platform secure-storage (SAF) secret store.

/// Secure storage for the auto-backup encryption password.
abstract interface class Keychain {
  /// Persists [value] under [key]. Returns whether the write succeeded.
  Future<bool> setSecret(String key, String value);

  /// Returns the value stored under [key], or null if absent.
  Future<String?> getSecret(String key);

  /// Removes the value stored under [key].
  Future<void> clearSecret(String key);
}
