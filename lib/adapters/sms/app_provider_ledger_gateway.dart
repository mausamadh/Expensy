// Adapter: implements the domain [LedgerGateway] port over AppProvider's
// addTransaction/addTransfer. This is the only place the SMS import context
// reaches into the ledger; it bridges until the ledger context is migrated
// (Phase 2).
import '../../domain/sms_import/ports/ports.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';

class AppProviderLedgerGateway implements LedgerGateway {
  final AppProvider _provider;

  const AppProviderLedgerGateway(this._provider);

  @override
  Future<String?> addTransaction({
    required String id,
    required String type,
    required double amount,
    required String description,
    required String accountId,
    required String categoryId,
    required DateTime date,
    String? note,
  }) async {
    final tx = AppTransaction(
      id: id,
      type: type,
      amount: amount,
      description: description,
      accountId: accountId,
      categoryId: categoryId,
      date: date,
      note: note ?? '',
    );
    await _provider.addTransaction(tx);
    return tx.id;
  }

  @override
  Future<String?> addTransfer({
    required String fromId,
    required String toId,
    required double fromAmount,
    required String title,
    required DateTime date,
  }) async {
    final debit = await _provider.addTransfer(
      fromId: fromId,
      toId: toId,
      fromAmount: fromAmount,
      title: title,
      date: date,
    );
    return debit?.id;
  }
}
