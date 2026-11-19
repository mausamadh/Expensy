import 'package:get_it/get_it.dart';

import '../adapters/backup/drift_backup_data_repository.dart';
import '../adapters/backup/expensy_saf_keychain.dart';
import '../adapters/backup/safety_snapshot_store.dart';
import '../adapters/budgeting/drift_budget_write_repository.dart';
import '../adapters/categories/drift_category_store.dart';
import '../adapters/fx/http_exchange_rate_provider.dart';
import '../adapters/goals/drift_goals_repository.dart';
import '../adapters/lended/drift_lended_repository.dart';
import '../adapters/ledger/drift_ledger_repositories.dart';
import '../adapters/ledger/drift_ledger_write_repositories.dart';
import '../adapters/ledger/drift_preset_repository.dart';
import '../adapters/loans/drift_loan_repository.dart';
import '../adapters/sms/app_provider_ledger_context.dart';
import '../adapters/sms/app_provider_ledger_gateway.dart';
import '../adapters/sms/drift_sms_repositories.dart';
import '../adapters/sms/expensy_sms_source.dart';
import '../adapters/sms/shared_prefs_sms_settings.dart';
import '../adapters/sms/template_registry_loader.dart';
import '../adapters/time/system_clock.dart';
import '../adapters/wealth/drift_asset_repository.dart';
import '../application/backup/backup_use_cases.dart';
import '../application/mutation_gate.dart';
import '../domain/backup/backup_validator.dart';
import '../domain/backup/ports/ports.dart';
import '../domain/budgeting/ports/budget_write_port.dart';
import '../domain/categories/ports/category_store.dart';
import '../domain/fx/ports/exchange_rate_provider.dart';
import '../domain/goals/ports/goals_repository.dart';
import '../domain/lended/ports/lended_repository.dart';
import '../domain/ledger/ports/ports.dart';
import '../domain/ledger/ports/preset_repository.dart';
import '../domain/ledger/ports/write_ports.dart';
import '../domain/loans/ports/loan_repository.dart';
import '../domain/shared/clock.dart';
import '../domain/sms_import/ports/ports.dart';
import '../domain/wealth/ports/asset_repository.dart';
import '../database/app_database.dart';
import '../providers/app_provider.dart';
import '../presentation/viewmodels/assets_view_model.dart';
import '../presentation/viewmodels/categories_view_model.dart';
import '../presentation/viewmodels/goals_view_model.dart';
import '../presentation/viewmodels/lended_view_model.dart';
import '../presentation/viewmodels/loans_view_model.dart';
import '../presentation/viewmodels/presets_view_model.dart';
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

    // FX read port (Phase 4) — exchange rates over the HTTP/cache adapter.
    getIt.registerSingleton<ExchangeRateProvider>(HttpExchangeRateProvider());

    // Ledger read ports (Phase 2a) — stateless Drift adapters over the
    // existing AppDatabase. Resolved by ledger use cases (Phase 2b).
    getIt.registerSingleton<AccountRepository>(const DriftAccountRepository());
    getIt.registerSingleton<CategoryRepository>(const DriftCategoryRepository());
    getIt.registerSingleton<TransactionRepository>(
        const DriftTransactionRepository());

    // Ledger write ports (Phase 2b) — atomic balance-mutating writes.
    getIt.registerSingleton<TransactionWriteRepository>(
        const DriftTransactionWriteRepository());
    getIt.registerSingleton<AccountWriteRepository>(
        const DriftAccountWriteRepository());
    getIt.registerSingleton<CategoryWriteRepository>(
        const DriftCategoryWriteRepository());

    // Budgeting write port (Phase 3) — budget persistence.
    getIt.registerSingleton<BudgetWriteRepository>(
        const DriftBudgetWriteRepository());

    // Wealth persistence port (Phase 6) — asset (valuables) storage.
    getIt.registerSingleton<AssetRepository>(const DriftAssetRepository());

    // Ledger persistence port (Phase 6) — transaction preset storage.
    getIt.registerSingleton<PresetRepository>(const DriftPresetRepository());

    // Goals persistence port (Phase 6) — wishlist + savings-goal storage.
    getIt.registerSingleton<GoalsRepository>(const DriftGoalsRepository());

    // Lended persistence port (Phase 6) — lended people + lended-money
    // ledger storage.
    getIt.registerSingleton<LendedRepository>(const DriftLendedRepository());

    // Loans persistence port (Phase 6) — loans + loan-payment ledger
    // storage.
    getIt.registerSingleton<LoanRepository>(const DriftLoanRepository());

    // Categories persistence port (Phase 6) — user categories +
    // subcategories. Distinct from the ledger's read-only
    // CategoryRepository above.
    getIt.registerSingleton<CategoryStore>(const DriftCategoryStore());

    // Backup ports (Phase 5) — data export/import, keychain, safety
    // snapshots. Resolved by the backup use cases below.
    getIt.registerSingleton<BackupDataRepository>(
        const DriftBackupDataRepository());
    getIt.registerSingleton<Keychain>(const ExpensySafKeychain());
    getIt.registerSingleton<SafetySnapshotStore>(
        const FileSafetySnapshotStore());
    getIt.registerSingleton<BackupValidator>(
        BackupValidator(
            currentSchemaVersion: AppDatabase.currentSchemaVersion));

    // Backup use cases (Phase 5).
    getIt.registerLazySingleton<CreateBackup>(
      () => CreateBackup(
        data: getIt<BackupDataRepository>(),
        clock: getIt<Clock>(),
      ),
    );
    getIt.registerLazySingleton<CreateSelectiveBackup>(
      () => CreateSelectiveBackup(
        data: getIt<BackupDataRepository>(),
        clock: getIt<Clock>(),
      ),
    );
    getIt.registerLazySingleton<RestoreBackup>(
      () => RestoreBackup(
        data: getIt<BackupDataRepository>(),
        validator: getIt<BackupValidator>(),
        snapshots: getIt<SafetySnapshotStore>(),
        clock: getIt<Clock>(),
      ),
    );
    getIt.registerLazySingleton<RestoreSelective>(
      () => RestoreSelective(
        data: getIt<BackupDataRepository>(),
        validator: getIt<BackupValidator>(),
        snapshots: getIt<SafetySnapshotStore>(),
        clock: getIt<Clock>(),
      ),
    );
    getIt.registerLazySingleton<CreateSafetySnapshot>(
      () => CreateSafetySnapshot(
        data: getIt<BackupDataRepository>(),
        snapshots: getIt<SafetySnapshotStore>(),
        clock: getIt<Clock>(),
      ),
    );
    getIt.registerLazySingleton<UndoLastRestore>(
      () => UndoLastRestore(
        data: getIt<BackupDataRepository>(),
        snapshots: getIt<SafetySnapshotStore>(),
      ),
    );
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

  /// Registers the Assets view model (Phase 6).
  ///
  /// Called from `main()` right after the [AppProvider] is constructed and
  /// BEFORE `provider.load()` runs, because `load()` assigns the asset list
  /// through the provider's delegating setter, which requires the view model
  /// to already be wired. The view model captures the provider's FX
  /// conversion and net-worth snapshot hooks as tear-offs.
  static void initAssets(AppProvider provider) {
    getIt.registerLazySingleton<AssetsViewModel>(
      () => AssetsViewModel(
        repository: getIt<AssetRepository>(),
        convertToMain: provider.convertToMain,
        onNetWorthChanged: provider.recordNetWorthSnapshot,
      ),
    );
    provider.wireAssetsVm(getIt<AssetsViewModel>());
  }

  /// Registers the Presets view model (Phase 6).
  ///
  /// Called from `main()` right after the [AppProvider] is constructed and
  /// BEFORE `provider.load()` runs, because `load()` assigns the preset list
  /// through the provider's delegating setter, which requires the view model
  /// to already be wired.
  static void initPresets(AppProvider provider) {
    getIt.registerLazySingleton<PresetsViewModel>(
      () => PresetsViewModel(repository: getIt<PresetRepository>()),
    );
    provider.wirePresetsVm(getIt<PresetsViewModel>());
  }

  /// Registers the Goals view model (Phase 6).
  ///
  /// Called from `main()` right after the [AppProvider] is constructed and
  /// BEFORE `provider.load()` runs, because `load()` assigns the
  /// wishlist/savings-goal/contribution lists through the provider's
  /// delegating setters, which require the view model to already be wired.
  static void initGoals(AppProvider provider) {
    getIt.registerLazySingleton<GoalsViewModel>(
      () => GoalsViewModel(repository: getIt<GoalsRepository>()),
    );
    provider.wireGoalsVm(getIt<GoalsViewModel>());
  }

  /// Registers the Lended view model (Phase 6).
  ///
  /// Called from `main()` right after the [AppProvider] is constructed and
  /// BEFORE `provider.load()` runs, because `load()` assigns the
  /// lended-people / lended-money lists through the provider's delegating
  /// setters, which require the view model to already be wired. The view
  /// model captures the provider's balance-delta, net-worth, and mutation
  /// mutex hooks as tear-offs so lended mutations stay atomic with the
  /// provider's own writes.
  static void initLended(AppProvider provider) {
    getIt.registerLazySingleton<LendedViewModel>(
      () => LendedViewModel(
        repository: getIt<LendedRepository>(),
        applyBalanceDelta: (accountId, delta) =>
            AppDatabase.instance.applyBalanceDelta(accountId, delta),
        balanceAccountIdFor: provider.balanceAccountIdFor,
        refreshAccounts: provider.refreshAccountsFromDb,
        onNetWorthChanged: provider.recordNetWorthSnapshot,
        personName: (id) => provider.personById(id)?.name,
        currency: () => provider.settings.currency,
        serializeMutation: provider.serializeMutation,
      ),
    );
    provider.wireLendedVm(getIt<LendedViewModel>());
  }

  /// Registers the Loans view model (Phase 6).
  ///
  /// Called from `main()` right after the [AppProvider] is constructed and
  /// BEFORE `provider.load()` runs, because `load()` assigns the loans /
  /// loan-payments lists through the provider's delegating setters, which
  /// require the view model to already be wired. The view model captures
  /// the provider's account-balance-delta, net-worth, and mutation-mutex
  /// hooks as tear-offs so loan mutations stay atomic with the provider's
  /// own writes.
  static void initLoans(AppProvider provider) {
    getIt.registerLazySingleton<LoansViewModel>(
      () => LoansViewModel(
        repository: getIt<LoanRepository>(),
        applyAccountBalanceDelta: provider.applyAccountBalanceDelta,
        onNetWorthChanged: provider.recordNetWorthSnapshot,
        serializeMutation: provider.serializeMutation,
      ),
    );
    provider.wireLoansVm(getIt<LoansViewModel>());
  }

  /// Registers the Categories view model (Phase 6) and wires it into the
  /// provider. Categories have no ledger side effects, so the view model
  /// only needs the CategoryStore port.
  static void initCategories(AppProvider provider) {
    getIt.registerLazySingleton<CategoriesViewModel>(
      () => CategoriesViewModel(
        store: getIt<CategoryStore>(),
        serializeMutation: provider.serializeMutation,
      ),
    );
    provider.wireCategoriesVm(getIt<CategoriesViewModel>());
  }

  /// Test hook: clears all registrations so a test can build its own
  /// graph (fakes). Not for use in app code.
  static void resetForTesting() {
    getIt.reset();
    _initialized = false;
  }
}
