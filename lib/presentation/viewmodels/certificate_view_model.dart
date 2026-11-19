// lib/presentation/viewmodels/certificate_view_model.dart
//
// Presentation-layer view model for the Certificates bounded context
// (Phase 6, "Slim the provider") — the user's fixed-income certificates
// (time deposits / FDs), their periodic yield payouts, and redemption.
//
// Owns the `certificates` list and the derived `totalCertificatesValue`.
// Every mutation is delegated to the [CertificateStore] port and serialized
// through the provider's zone-based mutation mutex so certificate writes
// stay atomic with the provider's own ledger writes.
//
// Cross-cutting couplings are injected as functions rather than a provider
// reference, keeping this file free of any `providers/` or `database/`
// import:
//   * [addTransaction] / [updateTransaction] — create/update the ledger
//     entry for the certificate principal, yield, and redemption.
//   * [newId] — id generator (shared with the provider).
//   * [convertToMain] — currency conversion for the derived total.
//   * [deleteTransactionsWithBalance] — the delete-cascade primitive
//     (reverse balance deltas, drop splits, remove the in-memory
//     transactions).
//   * [transactions] — read access to the ledger (principal-lookup +
//     related-transaction discovery).
//   * [recordNetWorthSnapshot] / [updateHomeWidgets] — post-mutation
//     side effects.
//   * [scheduleReminder] / [cancelReminder] — notification scheduling.
//   * [serializeMutation] — the provider's zone-based mutation mutex.
//
// Layering: this file lives in `presentation/` and imports only `domain/`
// and `models/` — never `adapters/` or `database/`. The store is injected
// through the constructor by the composition root.

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'package:finwick/domain/certificates/ports/certificate_store.dart';
import 'package:finwick/models/models.dart';

class CertificateViewModel extends ChangeNotifier {
  CertificateViewModel({
    required CertificateStore store,
    required Future<void> Function(AppTransaction t) addTransaction,
    required Future<void> Function(
      AppTransaction updated,
      AppTransaction original,
    ) updateTransaction,
    required String Function() newId,
    required double Function(double amount, String fromCurrency) convertToMain,
    required Future<void> Function(List<AppTransaction> txs)
        deleteTransactionsWithBalance,
    required List<AppTransaction> Function() transactions,
    required Future<void> Function() recordNetWorthSnapshot,
    required void Function() updateHomeWidgets,
    required Future<void> Function(Certificate c) scheduleReminder,
    required Future<void> Function(String id) cancelReminder,
    required Future<T> Function<T>(Future<T> Function()) serializeMutation,
  })  : _store = store,
        _addTransaction = addTransaction,
        _updateTransaction = updateTransaction,
        _newId = newId,
        _convertToMain = convertToMain,
        _deleteTransactionsWithBalance = deleteTransactionsWithBalance,
        _transactions = transactions,
        _recordNetWorthSnapshot = recordNetWorthSnapshot,
        _updateHomeWidgets = updateHomeWidgets,
        _scheduleReminder = scheduleReminder,
        _cancelReminder = cancelReminder,
        _serializeMutation = serializeMutation;

  final CertificateStore _store;
  final Future<void> Function(AppTransaction t) _addTransaction;
  final Future<void> Function(
    AppTransaction updated,
    AppTransaction original,
  ) _updateTransaction;
  final String Function() _newId;
  final double Function(double amount, String fromCurrency) _convertToMain;
  final Future<void> Function(List<AppTransaction> txs)
      _deleteTransactionsWithBalance;
  final List<AppTransaction> Function() _transactions;
  final Future<void> Function() _recordNetWorthSnapshot;
  final void Function() _updateHomeWidgets;
  final Future<void> Function(Certificate c) _scheduleReminder;
  final Future<void> Function(String id) _cancelReminder;
  final Future<T> Function<T>(Future<T> Function()) _serializeMutation;

  // ── State ──────────────────────────────────────────────────────────────
  List<Certificate> _certificates = [];

  /// All certificates (creation order per the DB query).
  List<Certificate> get certificates => _certificates;

  /// Replaces the certificate list (fresh-list reactivity rule: reassign,
  /// never mutate in place) and notifies listeners.
  set certificates(List<Certificate> next) {
    _certificates = next;
    notifyListeners();
  }

  /// Active (unsettled) certificate value converted to the main currency.
  double get totalCertificatesValue => _certificates
      .where((c) => !c.isSettled)
      .fold(0.0, (sum, c) => sum + _convertToMain(c.amount, c.currency));

  // ── Mutations ──────────────────────────────────────────────────────────
  Future<void> addCertificate(Certificate c) async {
    await _serializeMutation(() async {
      final now = DateTime.now();
      final tx = AppTransaction(
        id: _newId(),
        type: 'expense',
        amount: c.amount,
        description: 'Certificate Principal: ${c.name}',
        accountId: c.accountId,
        categoryId: 'sys_investment',
        date: now,
        note: 'Deposit for certificate: ${c.name} [cert:${c.id}]',
        currency: c.currency,
        certificateId: c.id,
      );
      await _addTransaction(tx);

      await _store.insertCertificate(c);
      certificates = [c, ...certificates];
      await _recordNetWorthSnapshot();
      await _scheduleReminder(c);
    });
  }

  Future<void> updateCertificate(Certificate c) async {
    await _serializeMutation(() async {
      final oldCert = _certificates.firstWhereOrNull((item) => item.id == c.id);
      if (oldCert != null &&
          (oldCert.amount != c.amount || oldCert.accountId != c.accountId)) {
        final principalTx = _transactions().firstWhereOrNull((t) =>
            (t.certificateId == c.id || t.note.contains('[cert:${c.id}]')) &&
            (t.description.startsWith('Certificate Principal:') ||
                t.note.contains('Deposit for certificate:')));
        if (principalTx != null) {
          final updatedTx = principalTx.copyWith(
            amount: c.amount,
            accountId: c.accountId,
            currency: c.currency,
          );
          await _updateTransaction(updatedTx, principalTx);
        }
      }
      await _store.updateCertificate(c);
      final idx = _certificates.indexWhere((item) => item.id == c.id);
      if (idx != -1) {
        final next = List<Certificate>.from(_certificates);
        next[idx] = c;
        certificates = next;
      }
      await _recordNetWorthSnapshot();
      await _scheduleReminder(c);
    });
  }

  Future<void> deleteCertificate(String id) async {
    await _serializeMutation(() async {
      await _cancelReminder(id);
      final cert = _certificates.firstWhereOrNull((c) => c.id == id);
      if (cert != null) {
        // Find all transactions associated with this certificate via ID,
        // tag, or exact legacy prefix (B12).
        final relatedTxs = _transactions().where((t) {
          final hasCertId = t.certificateId == id;
          final hasCertTag = t.note.contains('[cert:$id]');
          final matchesLegacyExact = t.certificateId == null &&
              t.accountId == cert.accountId &&
              (t.description == 'Certificate Principal: ${cert.name}' ||
                  t.description == 'Certificate Yield: ${cert.name}' ||
                  t.description == 'Certificate Redemption: ${cert.name}');
          return hasCertId || hasCertTag || matchesLegacyExact;
        }).toList();

        // Delete each transaction, automatically reverting its balance delta.
        await _deleteTransactionsWithBalance(relatedTxs);
      }

      await _store.deleteCertificate(id);
      certificates = certificates.where((item) => item.id != id).toList();
      _updateHomeWidgets();
      await _recordNetWorthSnapshot();
    });
  }

  Future<void> redeemCertificate(String id, {bool returnPrincipal = true}) async {
    await _serializeMutation(() async {
      await _cancelReminder(id);
      final cert = _certificates.firstWhereOrNull((c) => c.id == id);
      if (cert == null || cert.isSettled) return;

      if (returnPrincipal) {
        final now = DateTime.now();
        final tx = AppTransaction(
          id: _newId(),
          type: 'income',
          amount: cert.amount,
          description: 'Certificate Redemption: ${cert.name}',
          accountId: cert.accountId,
          categoryId: 'sys_investment',
          date: now,
          note: 'Principal return for ${cert.name} [cert:${cert.id}]',
          currency: cert.currency,
          certificateId: cert.id,
        );
        await _addTransaction(tx);
      }

      final settled = cert.copyWith(isSettled: true);
      await _store.updateCertificate(settled);
      final idx = _certificates.indexWhere((item) => item.id == id);
      if (idx != -1) {
        final next = List<Certificate>.from(_certificates);
        next[idx] = settled;
        certificates = next;
      }
      await _recordNetWorthSnapshot();
    });
  }

  /// Bounded catch-up of due yield payouts (up to 24 cycles per certificate),
  /// then redemption after maturity. Called on load and after restore.
  Future<void> checkAndProcessCertificates() async {
    await _serializeMutation(() async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final endOfToday =
          DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      for (var c in List<Certificate>.from(_certificates)) {
        if (c.isSettled) continue;

        final endOfCert = DateTime(
          c.endDate.year,
          c.endDate.month,
          c.endDate.day,
          23,
          59,
          59,
          999,
        );

        // Catch-up due payouts up to maturity date (bounded to 24 cycles).
        int iterations = 0;
        while (iterations < 24) {
          final nextDate = c.nextUncollectedPeriodDate;
          if (nextDate != null &&
              !nextDate.isAfter(endOfToday) &&
              !nextDate.isAfter(endOfCert)) {
            final payout = c.periodicPayout;
            if (payout > 0) {
              final tx = AppTransaction(
                id: _newId(),
                type: 'income',
                amount: payout,
                description: 'Certificate Yield: ${c.name}',
                accountId: c.accountId,
                categoryId: 'sys_investment',
                date: nextDate,
                note: 'Yield collection for ${c.name} [cert:${c.id}]',
                currency: c.currency,
                certificateId: c.id,
              );
              await _addTransaction(tx);

              c = c.copyWith(
                lastCollectedDate: nextDate,
                totalCollectedAmount: c.totalCollectedAmount + payout,
              );
              await _store.updateCertificate(c);
              final idx = _certificates.indexWhere((item) => item.id == c.id);
              if (idx != -1) {
                final nextCerts = List<Certificate>.from(_certificates);
                nextCerts[idx] = c;
                certificates = nextCerts;
              }
              iterations++;
            } else {
              break;
            }
          } else {
            break;
          }
        }

        // Only redeem after due yield has been collected up to endDate.
        final endDay = DateTime(c.endDate.year, c.endDate.month, c.endDate.day);
        if (today.isAfter(endDay)) {
          await redeemCertificate(c.id, returnPrincipal: true);
        }
      }
    });
  }
}
