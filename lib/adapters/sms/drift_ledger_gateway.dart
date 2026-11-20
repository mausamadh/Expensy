import 'package:finwick/application/ledger/ledger_write_use_cases.dart'
    show AddTransaction, AddTransfer, LedgerContext;
import 'package:finwick/domain/ledger/balance_delta.dart';
import 'package:finwick/domain/ledger/ports/ports.dart';
import 'package:finwick/domain/ledger/ports/write_ports.dart';
import 'package:finwick/domain/sms_import/ports/ports.dart' hide LedgerContext;
import 'package:finwick/models/models.dart';

class DriftLedgerGateway implements LedgerGateway {
  DriftLedgerGateway({
    required this.accounts,
    required this.transactions,
    required this.settingsCurrency,
    required this.exchangeRates,
    required this.onLedgerChanged,
  });

  final AccountRepository accounts;
  final TransactionWriteRepository transactions;
  final String Function() settingsCurrency;
  final Map<String, double> Function() exchangeRates;
  final Future<void> Function() onLedgerChanged;

  Future<LedgerContext> _context() async {
    final allAccounts = await accounts.getAll();
    final byId = <String, Account>{
      for (final account in allAccounts) account.id: account,
    };
    return LedgerContext(
      accountById: (id) => byId[id],
      settingsCurrency: settingsCurrency(),
      exchangeRates: exchangeRates(),
    );
  }

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
    final result = await AddTransaction(
      transactions: transactions,
      balance: const BalanceDeltaService(),
    ).call(tx, await _context());
    await onLedgerChanged();
    return result.tx.id;
  }

  @override
  Future<String?> addTransfer({
    required String fromId,
    required String toId,
    required double fromAmount,
    required String title,
    required DateTime date,
  }) async {
    final result = await AddTransfer(
      transactions: transactions,
      balance: const BalanceDeltaService(),
    ).call(
      fromId: fromId,
      toId: toId,
      fromAmount: fromAmount,
      title: title,
      date: date,
      ctx: await _context(),
    );
    if (result == null) return null;
    await onLedgerChanged();
    return result.debit.id;
  }
}
