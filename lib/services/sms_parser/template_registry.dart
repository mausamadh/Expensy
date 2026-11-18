import 'fallback_matcher.dart';
import 'parse_result.dart';
import 'parser_template.dart';
import 'template_parser.dart';
import 'transaction_gate.dart';
import 'transaction_type.dart';

/// Routes messages to templates by sender directory, then falls back to the
/// keyword-tier [FallbackMatcher] for un-routed but transaction-shaped
/// messages. List order is routing precedence. Duplicate template ids
/// resolve to the highest [ParserTemplate.revision]; `isActive = false`
/// drops an id entirely.
class TemplateRegistry {
  final List<ParserTemplate> templates;
  final bool fallbackEnabled;
  late final Map<String, List<ParserTemplate>> _routesBySender;

  TemplateRegistry(List<ParserTemplate> input, {this.fallbackEnabled = true})
      : templates = List.unmodifiable(_resolve(input)) {
    final routes = <String, List<ParserTemplate>>{};
    for (final t in templates) {
      routes.putIfAbsent(normalizeSenderId(t.senderId), () => []).add(t);
    }
    _routesBySender = routes;
  }

  static List<ParserTemplate> _resolve(List<ParserTemplate> input) {
    final winners = <String, ParserTemplate>{};
    for (final template in input) {
      final kept = winners[template.id];
      if (kept == null || template.revision > kept.revision) {
        winners[template.id] = template;
      }
    }
    return winners.values.where((t) => t.isActive).toList();
  }

  /// Templates that claim this sender, in routing-precedence order.
  List<ParserTemplate> routesFor(String senderId) =>
      _routesBySender[normalizeSenderId(senderId)] ?? const [];

  /// Parse one message.
  ///
  /// [defaultCurrency] is an ISO code stamped onto fallback-matched rows
  /// whose text names no currency; they keep `currencyDeclared = false`.
  /// Template-parsed rows carry only the currency the text names. No
  /// implicit default is ever applied.
  ///
  /// [preferMonthFirst] reads ambiguous numeric dates as month-first
  /// (05/03/2026 = May 3); day-first stays the default (March 5).
  Future<ParseResult> parse(
    String senderId,
    String body,
    DateTime timestamp, {
    String? defaultCurrency,
    bool preferMonthFirst = false,
  }) async {
    ParseFailure? incomplete;
    for (final template in routesFor(senderId)) {
      final result =
          await TemplateParser(template).parse(body, timestamp, preferMonthFirst: preferMonthFirst);
      if (result is ParseSuccess) return result;
      if (result is ParseFailure &&
          result.reason == ParseFailureReason.incomplete) {
        incomplete = result;
      }
    }
    // An INCOMPLETE means the message belongs to a routed provider shape;
    // do not fall back past a recognized shape.
    if (incomplete != null) return incomplete;
    if (fallbackEnabled && TransactionGate.isCandidate(body)) {
      return FallbackMatcher.detect(senderId, body, timestamp,
          defaultCurrency: defaultCurrency, preferMonthFirst: preferMonthFirst);
    }
    final detail =
        fallbackEnabled ? 'not transaction-shaped' : 'fallback disabled';
    return ParseFailure(ParseFailureReason.noRoute, detail: detail);
  }

  /// One load path for built-in and contributor templates: decode
  /// [ParserTemplate] JSON strings and build the registry over them.
  static TemplateRegistry fromTemplateJson(List<String> texts) =>
      TemplateRegistry(texts.map(ParserTemplate.decode).toList());
}
