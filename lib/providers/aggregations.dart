// lib/providers/aggregations.dart
//
// Re-export shim. The pure financial aggregation engine now lives in the
// domain layer (lib/domain/budgeting/aggregations.dart) per the hexagonal
// migration (HEXAGONAL_MIGRATION_PLAN.md §4.3). This file is kept so existing
// import sites (screens, services, tests) continue to work unchanged.

export '../domain/budgeting/aggregations.dart';
