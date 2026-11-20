// Shared sender/keyword tier. The registry routes on this gate and
// FallbackMatcher classifies with the same regexes, byte-identical, so both
// legs agree on what counts as a transaction-shaped message.
class TransactionGate {
  static final transactionCues = RegExp(
      r'\b(?:confirmed|received|paid|sent|transfer(?:red)?|withdraw(?:al|n)?|debited|deducted|credited|transaction|bought|purchase|deposit(?:ed)?|charged)\b',
      caseSensitive: false);

  // Uppercase-only CR/DR: bank statements mark direction with a standalone
  // "CR"/"DR" token (e.g. "has been CR Rs 10000.00"). Lowercase "cr"/"dr"
  // are ordinary words, so this cue is case-sensitive and kept separate —
  // Dart's RegExp has no inline flag toggles.
  static final crDrCues = RegExp(r'\b(?:CR|DR)\b');

  static final blockerCues = RegExp(
      r'\b(?:otp|password|win|promo|subscribe|click)\b'
      r'|\bone time\b|\bverification code\b|\bloan offer\b'
      r'|\b(?:activation|authorization|authorisation) code\b'
      r'|\bfailed\b|cannot complete|could not be completed|was not completed'
      r'|\binsufficient funds\b'
      r'|\bbonus airtime\b|\bstoro\b|make daily payments'
      r'|\b(?:total and min(?:imum)? amounts due|credit card (?:total )?due|minimum due|payment is due|please pay due)\b',
      caseSensitive: false);

  // Reversals must not be booked as expenses; without netting there is no
  // honest way to record them.
  static final reversalCues =
      RegExp(r'\b(?:reversed|reversal|refund(?:ed)?)\b', caseSensitive: false);

  static bool isCandidate(String body) =>
      (transactionCues.hasMatch(body) || crDrCues.hasMatch(body)) &&
      !blockerCues.hasMatch(body) &&
      !reversalCues.hasMatch(body);
}
