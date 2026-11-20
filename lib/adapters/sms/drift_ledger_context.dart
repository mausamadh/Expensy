import 'package:finwick/domain/sms_import/ports/ports.dart';
import 'package:finwick/providers/app_provider.dart';

class DriftLedgerContext implements LedgerContext {
  const DriftLedgerContext(this._provider);

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
