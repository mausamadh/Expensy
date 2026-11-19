// lib/domain/backup/entity_group_tables.dart
//
// Domain-owned mapping of user-facing entity groups to the database tables
// they span (hexagonal architecture, HEXAGONAL_MIGRATION_PLAN.md §5 Phase 5).
//
// Pure Dart — no Flutter, Drift, or plugin imports (enforced by ci_guard).
// Used by the selective backup/restore use cases and surfaced to the
// presentation layer via the provider.

/// Maps each selectable entity group to the set of tables it covers.
const Map<String, List<String>> entityGroupTables = {
  'accounts': ['accounts'],
  'transactions': ['transactions', 'transaction_splits', 'transaction_presets'],
  'categories': ['categories'],
  'recurring': ['recurring_payments', 'recurring_history'],
  'loans': ['loans', 'loan_payments'],
  'lent_money': ['lended_people', 'lended_money'],
  'certificates': ['certificates'],
  'budgets': ['budgets'],
  'assets': ['assets'],
  'wishlist_goals': ['wishlist', 'savings_goals', 'savings_contributions'],
};

/// Expands [groups] into the flat set of tables they cover.
Set<String> tablesForGroups(Set<String> groups) {
  final tables = <String>{};
  for (final group in groups) {
    final tList = entityGroupTables[group];
    if (tList != null) tables.addAll(tList);
  }
  return tables;
}
