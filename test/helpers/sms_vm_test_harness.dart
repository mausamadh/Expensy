// test/helpers/sms_vm_test_harness.dart
//
// Builds a real [SmsInboxViewModel] wired to the production adapters (Drift
// repositories, SharedPreferences settings, AppProvider ledger bridge) but
// with two fakes standing in for the device boundary:
//   * [FakeSmsSource] — returns domain [SmsMessage]s directly, replacing the
//     old `mockScan` MethodChannel mock.
//   * [FakeTemplateRegistryProvider] — returns an empty [TemplateRegistry]
//     (matching the old `SmsImportService(TemplateRegistry(const []))`
//     behaviour) so tests never read asset bundles.
//
// Tests keep [AppProvider] for account/category setup and ledger assertions;
// the view model owns the SMS slice.

import 'dart:async';

import 'package:finwick/adapters/sms/drift_ledger_context.dart';
import 'package:finwick/adapters/sms/drift_ledger_gateway.dart';
import 'package:finwick/adapters/ledger/drift_ledger_repositories.dart';
import 'package:finwick/adapters/ledger/drift_ledger_write_repositories.dart';
import 'package:finwick/adapters/sms/drift_sms_repositories.dart';
import 'package:finwick/adapters/sms/shared_prefs_sms_settings.dart';
import 'package:finwick/application/mutation_gate.dart';
import 'package:finwick/domain/shared/clock.dart';
import 'package:finwick/domain/sms_import/ports/ports.dart';
import 'package:finwick/domain/sms_import/sms_entities.dart';
import 'package:finwick/domain/sms_import/template_registry.dart';
import 'package:finwick/presentation/viewmodels/sms_inbox_view_model.dart';
import 'package:finwick/providers/app_provider.dart';

/// [SmsSource] fake: returns whatever [messages] is set to.
class FakeSmsSource implements SmsSource {
  List<SmsMessage> messages = const [];
  SmsPermissions permissions = const SmsPermissions(
    read: true,
    receive: true,
    isDefaultSmsApp: true,
  );
  SmsPermissions? requestedPermissions;

  @override
  Future<List<SmsMessage>> scanSms({
    int limit = 500,
    int? beforeTimestamp,
    String? beforeId,
  }) async {
    final beforeNumericId = beforeId == null ? null : int.tryParse(beforeId);
    final candidates = messages.where((message) {
      if (beforeTimestamp == null || message.timestamp < beforeTimestamp) {
        return true;
      }
      if (message.timestamp > beforeTimestamp || beforeNumericId == null) {
        return false;
      }
      final numericId = int.tryParse(message.id);
      return numericId != null && numericId < beforeNumericId;
    });
    return candidates.take(limit).toList();
  }

  @override
  Future<List<SmsSender>> getSenders() async => const [];

  @override
  Future<SmsPermissions> checkPermissions() async => permissions;

  @override
  Future<SmsPermissions> requestPermissions() async =>
      requestedPermissions ?? permissions;

  @override
  Stream<SmsMessage> startLiveCapture() => const Stream.empty();

  @override
  Future<void> stopLiveCapture() async {}
}

/// [TemplateRegistryProvider] fake: always returns an empty registry.
class FakeTemplateRegistryProvider implements TemplateRegistryProvider {
  const FakeTemplateRegistryProvider();

  @override
  Future<TemplateRegistry> load() async => TemplateRegistry(const []);
}

/// Fully-wired [SmsInboxViewModel] for integration tests.
class SmsVmHarness {
  SmsVmHarness(
    this.provider,
    this.source,
    this.clock, {
    this.notificationGateway,
  }) : vm = SmsInboxViewModel(
          source: source,
          inboxRepo: const DriftSmsInboxRepository(),
          ruleRepo: const DriftSmsRuleRepository(),
          prefRepo: const DriftSmsSenderPrefRepository(),
          senderAccountMappingRepo:
              const DriftSmsSenderAccountMappingRepository(),
          settings: const SharedPreferencesSmsSettings(),
          ledger: DriftLedgerGateway(
            accounts: const DriftAccountRepository(),
            transactions: const DriftTransactionWriteRepository(),
            settingsCurrency: () => provider.settings.currency,
            exchangeRates: () => provider.exchangeRates,
            onLedgerChanged: () async => provider.load(),
          ),
          ledgerContext: DriftLedgerContext(provider),
          registryProvider: const FakeTemplateRegistryProvider(),
          gate: MutationGate(),
          clock: clock,
          notificationGateway: notificationGateway,
        );

  final AppProvider provider;
  final FakeSmsSource source;
  final Clock clock;
  final SmsNotificationGateway? notificationGateway;
  final SmsInboxViewModel vm;

  /// Loads the view model's initial state from the repositories.
  Future<void> load() => vm.load();
}
