// Pure rule-matching and default-resolution logic for the SMS import
// context. Extracted from AppProvider so the application layer can use it
// without reaching into the provider. No Flutter, plugin, or DB imports.
import 'sms_entities.dart';
import 'sms_parser.dart';

/// Resolves which routing rule applies to an inbox item and computes the
/// default account/category/type/amount when the user does not override them.
class SmsRuleMatcher {
  const SmsRuleMatcher();

  /// Finds the first rule for [item]'s sender. A rule with no merchant
  /// pattern matches any message from that sender; a rule with a pattern
  /// matches when the parsed merchant contains the pattern (case-insensitive).
  SmsRule? matchRule(SmsInboxItem item, List<SmsRule> rules) {
    final candidates = rules.where((r) => r.senderId == item.senderId);
    for (final r in candidates) {
      if (r.merchantPattern == null || r.merchantPattern!.isEmpty) return r;
      final merchant = item.parsedMerchant ?? '';
      if (merchant.toLowerCase().contains(r.merchantPattern!.toLowerCase())) {
        return r;
      }
    }
    return null;
  }

  /// Maps a parsed transaction type to a ledger type.
  String typeFromParsed(String? parsedType) {
    switch (parsedType) {
      case 'income':
      case 'deposit':
        return 'income';
      case 'transfer':
        return 'transfer';
      default:
        return 'expense';
    }
  }

  /// Converts a parsed amount (minor units) to major units using the
  /// currency's ISO 4217 exponent. Returns 0 when the amount is null.
  double amountMajor(int? minor, String? currency) {
    if (minor == null) return 0;
    final exp = Iso4217.exponentFor(currency);
    var div = 1;
    for (var i = 0; i < exp; i++) {
      div *= 10;
    }
    return minor / div;
  }

  /// Default account: first non-credit account, else first account, else ''.
  String defaultAccountId(List<String> accountIds, List<String> accountTypes) {
    for (var i = 0; i < accountIds.length; i++) {
      if (accountTypes[i] != 'credit') return accountIds[i];
    }
    return accountIds.isNotEmpty ? accountIds.first : '';
  }

  /// Default category: for transfers, the system transfer category; else the
  /// first non-system category of the matching type. Returns '' when none.
  String defaultCategoryId(
    String type,
    List<String> categoryIds,
    List<String> categoryTypes,
    List<bool> categoryIsSystem,
  ) {
    if (type == 'transfer') return 'sys_transfer';
    final want = type == 'income' ? 'income' : 'expense';
    for (var i = 0; i < categoryIds.length; i++) {
      if (!categoryIsSystem[i] && categoryTypes[i] == want) {
        return categoryIds[i];
      }
    }
    return '';
  }

  /// Default transfer destination: first account that is not [fromId].
  String? transferToAccount(String fromId, List<String> accountIds) {
    for (final id in accountIds) {
      if (id != fromId) return id;
    }
    return null;
  }
}
