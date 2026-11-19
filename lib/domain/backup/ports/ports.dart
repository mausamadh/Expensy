// lib/domain/backup/ports/ports.dart
//
// Ports for the Backup bounded context (hexagonal architecture,
// HEXAGONAL_MIGRATION_PLAN.md §5 Phase 5).
//
// Domain-owned interfaces: the application layer programs against these, and
// adapters (lib/adapters/backup/) provide the concrete implementations. No
// Flutter, Drift, or plugin imports here (enforced by ci_guard).

export 'backup_data_repository.dart';
export 'keychain.dart';
export 'safety_snapshot_store.dart';
