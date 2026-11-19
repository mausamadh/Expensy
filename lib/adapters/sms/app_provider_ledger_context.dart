import 'package:finwick/domain/sms_import/ports/ports.dart';
import 'package:finwick/providers/app_provider.dart';

/// [LedgerContext] backed by [AppProvider].
///
/// Reads the provider's in-memory account/category lists and the default
/// currency, exposing them as parallel primitive lists so the domain's
/// [SmsRuleMatcher] can pick defaults without depending on the ledger's
/// model types.
class AppProviderLedgerContext implements LedgerContext {
  const AppProviderLedgerContext(this._provider);

  final AppProvider _provider;

  @override
  String get defaultCurrency => _provider.settings.currency;

  @override
  List<String> get accountIds => _provider.accounts.map((a) => a.id).toList();

  @override
  List<String> get accountTypes =>
      _provider.accounts.map((a) => a.type).toList();

  @override
  List<String> get categoryIds =>
      _provider.categories.map((c) => c.id).toList();

  @override
  List<String> get categoryTypes =>
      _provider.categories.map((c) => c.type).toList();

  @override
  List<bool> get categoryIsSystem =>
      _provider.categories.map((c) => c.isSystem).toList();
}
