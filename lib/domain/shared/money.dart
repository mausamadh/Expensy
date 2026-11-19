/// Immutable monetary amount stored as integer minor units (cents/paise)
/// with an ISO-4217 currency code.
///
/// This is the same shape the database already stores amounts in, so no
/// conversion is needed at the persistence boundary.
class Money {
  /// Amount in the currency's minor unit (e.g. paise for NPR, cents for USD).
  final int minorUnits;

  /// ISO-4217 code, e.g. `NPR`, `USD`.
  final String currencyCode;

  const Money(this.minorUnits, this.currencyCode);

  factory Money.zero(String currencyCode) => Money(0, currencyCode);

  bool get isZero => minorUnits == 0;
  bool get isPositive => minorUnits > 0;
  bool get isNegative => minorUnits < 0;

  bool sameCurrency(Money other) => currencyCode == other.currencyCode;

  Money add(Money other) {
    _requireSameCurrency(other);
    return Money(minorUnits + other.minorUnits, currencyCode);
  }

  Money subtract(Money other) {
    _requireSameCurrency(other);
    return Money(minorUnits - other.minorUnits, currencyCode);
  }

  Money negate() => Money(-minorUnits, currencyCode);

  /// Multiplies by a whole-number factor (e.g. splitting a transaction).
  Money times(int factor) => Money(minorUnits * factor, currencyCode);

  void _requireSameCurrency(Money other) {
    if (!sameCurrency(other)) {
      throw ArgumentError.value(
        other.currencyCode,
        'currencyCode',
        'Cannot combine $currencyCode with ${other.currencyCode}',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(minorUnits, currencyCode);

  @override
  String toString() => 'Money($minorUnits, $currencyCode)';
}
