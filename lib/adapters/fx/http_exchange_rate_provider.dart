// lib/adapters/fx/http_exchange_rate_provider.dart
//
// Adapter (hexagonal architecture, HEXAGONAL_MIGRATION_PLAN.md §5 Phase 4).
//
// Implements the domain `ExchangeRateProvider` port over the existing
// `ExchangeRateService` (open.er-api.com + gold API, SharedPreferences cache).
// This is the only place the FX concern touches the network/cache; the
// domain and application layers depend on the port, not on this class.

import '../../domain/fx/ports/exchange_rate_provider.dart';
import '../../services/exchange_rate_service.dart';

/// [ExchangeRateProvider] backed by [ExchangeRateService].
class HttpExchangeRateProvider implements ExchangeRateProvider {
  final ExchangeRateService _service;

  HttpExchangeRateProvider([ExchangeRateService? service])
      : _service = service ?? ExchangeRateService();

  @override
  Future<Map<String, double>> getRates() => _service.getRates();
}
