// Shared sender/keyword tier. The registry routes on this gate and
// FallbackMatcher classifies with the same regexes, byte-identical, so both
// legs agree on what counts as a transaction-shaped message.
class TransactionGate {
  static final transactionCues = RegExp(
      r'\b(?:confirmed|received|paid|sent|withdraw|debited|credited|transaction|bought|purchase|deposit|charged)\b',
      caseSensitive: false);

  static final blockerCues = RegExp(
      r'\b(?:otp|password|win|offer|promo|subscribe|click)\b'
      r'|\bone time\b|\bverification code\b|\bloan offer\b'
      r'|\b(?:activation|authorization|authorisation) code\b'
      r'|\bfailed\b|cannot complete|could not be completed|was not completed'
      r'|\binsufficient funds\b'
      r'|\bbonus airtime\b|\bstoro\b|make daily payments',
      caseSensitive: false);

  // Reversals must not be booked as expenses; without netting there is no
  // honest way to record them.
  static final reversalCues =
      RegExp(r'\b(?:reversed|reversal|refund(?:ed)?)\b', caseSensitive: false);

  static bool isCandidate(String body) =>
      transactionCues.hasMatch(body) &&
      !blockerCues.hasMatch(body) &&
      !reversalCues.hasMatch(body);
}
