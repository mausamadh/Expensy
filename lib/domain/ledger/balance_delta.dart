// lib/domain/ledger/balance_delta.dart
//
// Pure domain service for the Ledger bounded context (hexagonal architecture,
// Phase 2b).
//
// Encapsulates the atomic balance-delta rules that were previously inlined in
// `AppProvider` (`balanceAccountIdFor`, `txCurrency`, `_txDelta`). The service
// is dependency-free and deterministic: it operates on value objects (accounts,
// transactions, exchange rates) and throws [RatesUnavailableException] when a
// cross-currency mutation is attempted without usable rates.
//
// No Flutter, Drift, or plugin imports (enforced by ci_guard).

import 'package:finwick/models/models.dart';

import 'rates_unavailable_exception.dart';

/// Resolves an account by id. Returns null when the account does not exist.
typedef AccountLookup = Account? Function(String id);

/// Pure rules for computing the signed balance delta a transaction applies to
/// its balance account, including cross-currency conversion.
class BalanceDeltaService {
  const BalanceDeltaService();

  /// The account whose balance is actually mutated for a transaction recorded
  /// against [accountId]. A debit account with a non-empty
  /// [Account.linkedAccountId] routes to the linked account; everything else
  /// maps to itself.
  String balanceAccountIdFor(Account? account, String accountId) {
    if (account != null &&
        account.isDebit &&
        account.linkedAccountId != null &&
        account.linkedAccountId!.isNotEmpty) {
      return account.linkedAccountId!;
    }
    return accountId;
  }

  /// The effective currency of [t]: its own currency when set, otherwise the
  /// currency of the source account (the paid-via account, falling back to the
  /// balance account), otherwise [settingsCurrency].
  String txCurrency(
    AppTransaction t, {
    required AccountLookup accountById,
    required String settingsCurrency,
  }) {
    if (t.currency.isNotEmpty) return t.currency;
    final srcAcc = accountById(t.paidViaAccountId ?? t.accountId) ??
        accountById(balanceAccountIdFor(accountById(t.accountId), t.accountId));
    return srcAcc?.currency ?? settingsCurrency;
  }

  /// The signed balance delta (in the balance account's currency) that [t]
  /// applies. Income is positive, expense is negative. When [reverse] is true
  /// the sign is flipped (used to undo a previously applied delta).
  ///
  /// When the transaction currency differs from the balance account currency,
  /// the amount is converted using [exchangeRates]. If no usable rate exists
  /// and [requireRates] is true, a [RatesUnavailableException] is thrown;
  /// otherwise the unconverted amount is used.
  double txDelta(
    AppTransaction t, {
    required AccountLookup accountById,
    required String settingsCurrency,
    required Map<String, double> exchangeRates,
    bool reverse = false,
    bool requireRates = false,
  }) {
    final balAccId = balanceAccountIdFor(accountById(t.accountId), t.accountId);
    final balAcc = accountById(balAccId);
    final accCurrency = balAcc?.currency ?? settingsCurrency;
    final effTxCurrency = txCurrency(
      t,
      accountById: accountById,
      settingsCurrency: settingsCurrency,
    );

    var amount = t.amount;
    if (effTxCurrency != accCurrency) {
      final converted = convert(amount, effTxCurrency, accCurrency, exchangeRates);
      if (converted == null) {
        if (requireRates) throw const RatesUnavailableException();
      } else {
        amount = converted;
      }
    }

    final sign = t.type == 'income' ? 1.0 : -1.0;
    return (reverse ? -sign : sign) * amount;
  }

  /// Cross-currency conversion using per-currency rates expressed against a
  /// common base. Returns null when either rate is missing or the source rate
  /// is zero. [from] == [to] returns [amount] unchanged.
  double? convert(
    double amount,
    String from,
    String to,
    Map<String, double> rates,
  ) {
    if (from == to) return amount;
    final fromRate = rates[from];
    final toRate = rates[to];
    if (fromRate == null || toRate == null || fromRate == 0) return null;
    return amount / fromRate * toRate;
  }
}
