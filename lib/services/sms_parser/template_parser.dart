import 'amount_parser.dart';
import 'dedup.dart';
import 'iso4217.dart';
import 'message_date_parser.dart';
import 'parsed_transaction.dart';
import 'parse_result.dart';
import 'parser_template.dart';
import 'transaction_type.dart';

/// Authoritative sender normalization for routing: uppercase, then strip
/// every non-alphanumeric character ("M-PESA" -> "MPESA"). For routing only;
/// stored sender ids and rawHash inputs keep the template's declared sender
/// id.
String normalizeSenderId(String raw) =>
    raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

final _whitespaceRun = RegExp(r'\s+');

// Providers vary keyword and currency casing inside one format family
// ("Confirmed. Ksh" vs "Confirmed. KSH"), so anchors match case-insensitively
// while extracted values keep their original text.
int indexOfIgnoreCase(String haystack, String needle, int from) {
  if (needle.isEmpty) {
    return from < 0 ? 0 : (from > haystack.length ? haystack.length : from);
  }
  // Lowercase once, then use the native (fast) indexOf. The previous
  // per-position substring+toLowerCase scan was O(n·m) with an allocation at
  // every position and froze the UI thread while scanning the inbox.
  return haystack.toLowerCase().indexOf(needle.toLowerCase(), from);
}

// A "." terminator must end the sentence, not the decimal part of a value;
// "KSH32,071.36." ends at the dot after 36, not the one inside it. When a
// body has no sentence dot at all, the first dot is the best available cut.
int findTerminator(String body, String textAfter, int from) {
  if (textAfter != '.') return indexOfIgnoreCase(body, textAfter, from);
  var idx = indexOfIgnoreCase(body, textAfter, from);
  while (idx != -1 && idx + 1 < body.length && _isDigit(body.codeUnitAt(idx + 1))) {
    idx = indexOfIgnoreCase(body, textAfter, idx + 1);
  }
  return idx;
}

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

// Card terminals fill undecodable filler characters around a literal
// "no description" when they report no descriptor; strip the filler so the
// merchant renders as the text the bank actually sent.
String? cleanMerchant(String value) {
  final printable = value.replaceAll('\uFFFD', '').trim();
  return printable.isEmpty ? null : printable;
}

/// Applies one [ParserTemplate] to a message body: confirms every anchor,
/// slices the declared fields, and returns a [ParseResult]. Stateless;
/// [TemplateRegistry] owns routing and constructs one per parse.
class TemplateParser {
  TemplateParser(this.template);

  final ParserTemplate template;

  String get senderId => template.senderId;

  Future<ParseResult> parse(
      String body, DateTime timestamp, {bool preferMonthFirst = false}) async {
    final collapsed = body.replaceAll(_whitespaceRun, ' ');
    for (final anchor in template.anchors) {
      final beforeIndex = indexOfIgnoreCase(collapsed, anchor.textBefore, 0);
      if (beforeIndex == -1) {
        return const ParseFailure(ParseFailureReason.noMatch,
            detail: 'anchor mismatch');
      }
      final afterIndex = findTerminator(
          collapsed, anchor.textAfter, beforeIndex + anchor.textBefore.length);
      if (afterIndex == -1) {
        return const ParseFailure(ParseFailureReason.noMatch,
            detail: 'anchor mismatch');
      }
    }

    int? amountMinorUnits;
    String? currency;
    var currencyDeclared = false;
    String? merchant;
    String? reference;
    int? balanceMinorUnits;
    int? feeMinorUnits;
    var parsedTimestamp = timestamp;

    for (final field in template.fields) {
      final extracted = extractField(collapsed, field);
      switch (field.name) {
        case FieldName.amount:
          // Most templates consume the currency token inside the AMOUNT
          // anchor's textBefore, so detection spans the anchor text plus the
          // field slice.
          final detected =
              detectCurrencyCode(field.anchor.textBefore + (extracted ?? ''));
          amountMinorUnits = extracted == null
              ? null
              : parseAmountToMinorUnits(extracted, Iso4217.exponentFor(detected));
          currency = detected;
          currencyDeclared = detected != null;
        case FieldName.merchant:
          merchant = extracted == null ? null : cleanMerchant(extracted);
        case FieldName.reference:
          reference = extracted;
        case FieldName.balance:
          balanceMinorUnits = extracted == null
              ? null
              : parseAmountToMinorUnits(extracted, Iso4217.exponentFor(currency));
        case FieldName.fee:
          feeMinorUnits = extracted == null
              ? null
              : parseAmountToMinorUnits(extracted, Iso4217.exponentFor(currency));
        case FieldName.date:
          if (extracted != null) {
            // The template grammar is day-first; a month-first preference
            // only adds shapes day-first cannot read.
            parsedTimestamp = MessageDateParser.parseTemplateDate(extracted) ??
                (preferMonthFirst
                    ? MessageDateParser.parseFlexibleDate(extracted, true)
                    : null) ??
                parsedTimestamp;
          }
      }
    }

    final finalAmount = amountMinorUnits;
    if (finalAmount == null) {
      return const ParseFailure(ParseFailureReason.incomplete,
          detail: 'missing amount');
    }

    return ParseSuccess(
      ParsedTransaction(
        amountMinorUnits: finalAmount,
        currency: currency,
        currencyDeclared: currencyDeclared,
        type: template.transactionDirection,
        merchant: merchant,
        reference: reference,
        balanceMinorUnits: balanceMinorUnits,
        feeMinorUnits: feeMinorUnits,
        timestamp: parsedTimestamp,
        senderId: template.senderId,
        rawHash: await rawHashFor(template.senderId, body),
        body: body,
        parserRevision: template.revision,
      ),
      templateId: template.id,
    );
  }

  String? extractField(String body, TemplateField field) {
    final beforeIndex = indexOfIgnoreCase(body, field.anchor.textBefore, 0);
    if (beforeIndex == -1) return null;
    final start = beforeIndex + field.anchor.textBefore.length;
    // An empty after-anchor means the value runs to the end of the body.
    final afterIndex = field.anchor.textAfter.isEmpty
        ? body.length
        : findTerminator(body, field.anchor.textAfter, start);
    if (afterIndex == -1) return null;
    return body.substring(start, afterIndex).trim();
  }
}
