import 'package:get_it/get_it.dart';

import '../adapters/ledger/drift_ledger_repositories.dart';
import '../adapters/sms/app_provider_ledger_context.dart';
import '../adapters/sms/app_provider_ledger_gateway.dart';
import '../adapters/sms/drift_sms_repositories.dart';
import '../adapters/sms/expensy_sms_source.dart';
import '../adapters/sms/shared_prefs_sms_settings.dart';
import '../adapters/sms/template_registry_loader.dart';
import '../adapters/time/system_clock.dart';
import '../application/mutation_gate.dart';
import '../domain/ledger/ports/ports.dart';
import '../domain/shared/clock.dart';
import '../domain/sms_import/ports/ports.dart';
import '../providers/app_provider.dart';
import '../presentation/viewmodels/sms_inbox_view_model.dart';

/// Composition root: the ONLY place concrete adapters are constructed.
///
/// Everything else resolves dependencies from [getIt]. Call [init] once
/// from `main()` before the app (or any background entrypoint) starts
/// using services.
class CompositionRoot {
  CompositionRoot._();

  static final GetIt getIt = GetIt.instance;

  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    _initialized = true;

    // Cross-cutting ports
    getIt.registerSingleton<Clock>(SystemClock());
    getIt.registerSingleton<MutationGate>(MutationGate());

    // Ledger read ports (Phase 2a) — stateless Drift adapters over the
    // existing AppDatabase. Resolved by ledger use cases (Phase 2b).
    getIt.registerSingleton<AccountRepository>(const DriftAccountRepository());
    getIt.registerSingleton<CategoryRepository>(const DriftCategoryRepository());
    getIt.registerSingleton<TransactionRepository>(
        const DriftTransactionRepository());
  }

  /// Registers the SMS import context (adapters + view model).
  ///
  /// Called from `main()` after the [AppProvider] is constructed, because
  /// the ledger gateway/context adapters bridge to the provider until the
  /// ledger context is migrated (Phase 2).
  static void initSms(AppProvider provider) {
    getIt.registerSingleton<AppProvider>(provider);

    // Adapters (ports → concrete implementations)
    getIt.registerSingleton<SmsSource>(const ExpensySmsSource());
    getIt.registerSingleton<SmsInboxRepository>(const DriftSmsInboxRepository());
    getIt.registerSingleton<SmsRuleRepository>(const DriftSmsRuleRepository());
    getIt.registerSingleton<SmsSenderPrefRepository>(
        const DriftSmsSenderPrefRepository());
    getIt.registerSingleton<SmsSettings>(const SharedPreferencesSmsSettings());
    getIt.registerSingleton<LedgerGateway>(
        AppProviderLedgerGateway(provider));
    getIt.registerSingleton<LedgerContext>(AppProviderLedgerContext(provider));
    getIt.registerSingleton<TemplateRegistryProvider>(
        const TemplateRegistryLoader());

    // View model (presentation) — resolves its dependencies from [getIt].
    getIt.registerLazySingleton<SmsInboxViewModel>(
      () => SmsInboxViewModel(
        source: getIt<SmsSource>(),
        inboxRepo: getIt<SmsInboxRepository>(),
        ruleRepo: getIt<SmsRuleRepository>(),
        prefRepo: getIt<SmsSenderPrefRepository>(),
        settings: getIt<SmsSettings>(),
        ledger: getIt<LedgerGateway>(),
        ledgerContext: getIt<LedgerContext>(),
        registryProvider: getIt<TemplateRegistryProvider>(),
        gate: getIt<MutationGate>(),
        clock: getIt<Clock>(),
      ),
    );
  }

  /// Test hook: clears all registrations so a test can build its own
  /// graph (fakes). Not for use in app code.
  static void resetForTesting() {
    getIt.reset();
    _initialized = false;
  }
}
