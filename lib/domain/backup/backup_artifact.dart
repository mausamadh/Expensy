// lib/domain/backup/backup_artifact.dart
//
// Value object for a fully-built backup payload (hexagonal architecture,
// HEXAGONAL_MIGRATION_PLAN.md §5 Phase 5).
//
// Pure Dart — no Flutter, Drift, or plugin imports (enforced by ci_guard).
// The application layer produces this; the presentation layer hands the
// bytes to a file picker / SAF adapter to persist them.

import 'dart:typed_data';

/// An immutable, ready-to-persist backup payload.
class BackupArtifact {
  final Uint8List bytes;
  final String fileName;
  final String mimeType;

  const BackupArtifact({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });
}
