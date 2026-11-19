// test/helpers/certificate_test_harness.dart
//
// Shared widget-test harness for the Certificates view model (Phase 6).
//
// Screens that read the delegated `certificates` collection (or the derived
// `totalCertificatesValue` / `totalWealthAssets`) watch
// `CertificateViewModel`. Widget tests that mount those screens must
// therefore provide a `CertificateViewModel` in addition to `AppProvider`.
// This helper builds a VM backed by an in-memory fake store (no DB) and
// wraps a child in a `MultiProvider` exposing both notifiers.

import 'package:finwick/domain/certificates/ports/certificate_store.dart';
import 'package:finwick/models/models.dart';
import 'package:finwick/presentation/viewmodels/certificate_view_model.dart';
import 'package:finwick/providers/app_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// In-memory [CertificateStore] for widget tests — no DB access.
class InMemoryCertificateStore implements CertificateStore {
  List<Certificate> _certificates = [];

  @override
  Future<List<Certificate>> getCertificates() async =>
      List.unmodifiable(_certificates);

  @override
  Future<void> insertCertificate(Certificate c) async {
    _certificates = [c, ..._certificates];
  }

  @override
  Future<void> updateCertificate(Certificate c) async {
    _certificates = [for (final x in _certificates) x.id == c.id ? c : x];
  }

  @override
  Future<void> deleteCertificate(String id) async {
    _certificates = [for (final c in _certificates) if (c.id != id) c];
  }
}

/// Builds a [CertificateViewModel] backed by an in-memory fake store.
///
/// The cross-cutting hooks are no-ops in tests (no DB, no net-worth
/// snapshots, no notifications), so certificate mutations run against the
/// in-memory store only.
CertificateViewModel buildCertificateViewModel() => CertificateViewModel(
      store: InMemoryCertificateStore(),
      addTransaction: (t) async {},
      updateTransaction: (updated, original) async {},
      newId: () => 'cert-test-id',
      convertToMain: (amount, fromCurrency) => amount,
      deleteTransactionsWithBalance: (txs) async {},
      transactions: () => const [],
      recordNetWorthSnapshot: () async {},
      updateHomeWidgets: () {},
      scheduleReminder: (c) async {},
      cancelReminder: (id) async {},
      serializeMutation: <T>(Future<T> Function() action) => action(),
    );

/// Wraps [child] in a `MultiProvider` exposing [app] and a fresh
/// [CertificateViewModel], so screens that watch the certificate view model
/// (e.g. the certificates screens, or the net-worth/insights/more/backup
/// screens that read the derived totals) resolve it in tests.
///
/// The view model is wired into [app] first, so data assigned through the
/// provider's delegating setter (`app.certificates = ...`) lands in the view
/// model and its listeners fire.
Widget wrapWithCertificates(AppProvider app, Widget child) {
  final vm = buildCertificateViewModel();
  app.wireCertificateVm(vm);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppProvider>.value(value: app),
      ChangeNotifierProvider<CertificateViewModel>.value(value: vm),
    ],
    child: child,
  );
}
