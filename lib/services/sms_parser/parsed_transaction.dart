import 'iso4217.dart';
import 'transaction_type.dart';

/// One transaction extracted from one message.
///
/// Money is [amountMinorUnits] (int) scaled by the ISO 4217 exponent of
/// [currency] (KES 2, UGX 0): `"Ksh1,500.00"` is `150000`. [currency] is the
/// ISO code the text named; a fallback-matched row whose text named none
/// carries the caller's defaultCurrency, and a template-parsed row keeps null.
/// It is never silently defaulted inside the parser.
///
/// [rawHash] is a stable `senderId:body` digest for dedup; it deliberately
/// ignores the timestamp so a re-delivered copy collapses onto the first.
/// Fields the text does not carry stay null rather than defaulted.
class ParsedTransaction {
  final int amountMinorUnits;
  final String? currency;
  final TransactionType type;
  final String? merchant;
  final String? reference;
  final int? balanceMinorUnits;
  final int? feeMinorUnits;
  final DateTime timestamp;
  final String senderId;
  final String rawHash;
  final String body;
  final int parserRevision;
  final ParseConfidence confidence;

  /// False when the amount text named no currency, including fallback rows
  /// stamped with the consumer default; callers must not treat such rows as
  /// naming any currency.
  final bool currencyDeclared;

  /// Why a LOW-confidence row awaits review ("direction", "amount"); null
  /// when the row counted or nothing specific explains the flag.
  final String? reviewReason;

  const ParsedTransaction({
    required this.amountMinorUnits,
    required this.currency,
    required this.type,
    this.merchant,
    this.reference,
    this.balanceMinorUnits,
    this.feeMinorUnits,
    required this.timestamp,
    required this.senderId,
    required this.rawHash,
    this.body = '',
    this.parserRevision = 1,
    this.confidence = ParseConfidence.high,
    this.currencyDeclared = true,
    this.reviewReason,
  });

  /// The amount as a double in major units (e.g. 1500.00 for KES 150000).
  double get amountMajorUnits {
    final exp = Iso4217.exponentFor(currency);
    return amountMinorUnits / _pow10(exp);
  }

  static int _pow10(int e) {
    var r = 1;
    for (var i = 0; i < e; i++) {
      r *= 10;
    }
    return r;
  }
}
