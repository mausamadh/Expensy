// lib/domain/ledger/rates_unavailable_exception.dart
//
// Pure domain exception (hexagonal architecture, Phase 2b).
//
// Thrown by the ledger write use cases when a cross-currency transaction or
// transfer is attempted before live or cached exchange rates have loaded.
//
// This is the domain-owned exception. The presentation layer catches it and
// supplies the localized message (the domain has no l10n dependency).

/// Thrown when a cross-currency mutation requires exchange rates that are not
/// yet available.
class RatesUnavailableException implements Exception {
  const RatesUnavailableException();

  @override
  String toString() => 'RatesUnavailableException';
}
