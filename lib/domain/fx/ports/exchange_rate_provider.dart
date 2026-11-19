// lib/domain/fx/ports/exchange_rate_provider.dart
//
// Read-side port for the FX (exchange-rate) concern (hexagonal architecture,
// HEXAGONAL_MIGRATION_PLAN.md §5 Phase 4).
//
// Domain-owned interface for reading exchange rates. The application/domain
// layer programs against this; the HTTP adapter (lib/adapters/fx/) provides
// the concrete implementation over the existing `ExchangeRateService`
// (open.er-api.com + gold API, SharedPreferences cache). No Flutter, Drift,
// or plugin imports here (enforced by ci_guard).

/// Read access to exchange rates (currency code → rate relative to USD).
abstract interface class ExchangeRateProvider {
  /// Returns the current rates map (may be stale or empty when offline).
  Future<Map<String, double>> getRates();
}
