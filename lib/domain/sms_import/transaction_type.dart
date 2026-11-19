/// Money movement direction the template or fallback recognized.
enum TransactionType {
  income,
  expense,
  transfer,
  fee,
  withdrawal,
  deposit,
  unknown,
}

TransactionType parseTransactionType(String? s) {
  switch ((s ?? 'UNKNOWN').toUpperCase()) {
    case 'INCOME':
      return TransactionType.income;
    case 'EXPENSE':
      return TransactionType.expense;
    case 'TRANSFER':
      return TransactionType.transfer;
    case 'FEE':
      return TransactionType.fee;
    case 'WITHDRAWAL':
      return TransactionType.withdrawal;
    case 'DEPOSIT':
      return TransactionType.deposit;
    default:
      return TransactionType.unknown;
  }
}

/// Extraction trustworthiness. [high] rows can be counted as-is; [medium] and
/// [low] carry a reviewReason and expect a review step; [failed] marks an
/// attempt that produced no usable row.
enum ParseConfidence { high, medium, low, failed }

/// Why parsing produced no transaction.
/// - [noMatch]: the message looks transaction-shaped but no amount could be
///   extracted; for direct template use, also when a routed template's anchors
///   did not confirm.
/// - [incomplete]: a template's shape matched but the amount is missing;
///   review-worthy rather than discardable.
/// - [noRoute]: nothing parsed and the fallback leg did not run.
enum ParseFailureReason { noMatch, incomplete, noRoute }
