/// Dart port of the SMS transaction parser engine.
///
/// [TemplateRegistry] routes a message to sender templates and falls back
/// to the keyword-tier [FallbackMatcher]; both produce a [ParseResult]
/// carrying a [ParsedTransaction] or an explicit [ParseFailure].
library;

export 'amount_parser.dart';
export 'dedup.dart';
export 'fallback_matcher.dart';
export 'iso4217.dart';
export 'message_date_parser.dart';
export 'parsed_transaction.dart';
export 'parse_result.dart';
export 'parser_template.dart';
export 'sms_kind_classifier.dart';
export 'template_parser.dart';
export 'template_registry.dart';
export 'transaction_gate.dart';
export 'transaction_type.dart';
