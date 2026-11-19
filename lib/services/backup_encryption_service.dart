// lib/services/backup_encryption_service.dart
//
// Backward-compatibility shim. The implementation now lives in the domain
// layer (hexagonal architecture, HEXAGONAL_MIGRATION_PLAN.md §5 Phase 5).
// Existing importers (tests, auto_backup_service) keep working unchanged.

export 'package:finwick/domain/backup/backup_encryption_service.dart';
