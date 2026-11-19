import 'parsed_transaction.dart';
import 'transaction_type.dart';

/// Outcome of parsing one message: a [Success] carries a [ParsedTransaction],
/// a [Failure] carries a [ParseFailureReason] explaining why nothing was
/// produced. Parsers never return null-or-nothing; a message that looks like
/// a transaction but resists extraction fails with an explicit reason so the
/// caller can route it to review instead of losing it.
sealed class ParseResult {
  const ParseResult();
}

class ParseSuccess extends ParseResult {
  final ParsedTransaction transaction;
  final String? templateId;

  const ParseSuccess(this.transaction, {this.templateId});
}

class ParseFailure extends ParseResult {
  final ParseFailureReason reason;
  final String? detail;

  const ParseFailure(this.reason, {this.detail});
}
