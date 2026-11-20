// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'composition/root.dart';
import 'presentation/viewmodels/assets_view_model.dart';
import 'presentation/viewmodels/budgets_view_model.dart';
import 'presentation/viewmodels/certificate_view_model.dart';
import 'presentation/viewmodels/categories_view_model.dart';
import 'presentation/viewmodels/goals_view_model.dart';
import 'presentation/viewmodels/lended_view_model.dart';
import 'presentation/viewmodels/loans_view_model.dart';
import 'presentation/viewmodels/networth_view_model.dart';
import 'presentation/viewmodels/presets_view_model.dart';
import 'presentation/viewmodels/recurring_view_model.dart';
import 'presentation/viewmodels/sms_inbox_view_model.dart';
import 'presentation/viewmodels/transactions_view_model.dart';
import 'providers/app_provider.dart';
import 'l10n/app_localizations.dart';
import 'theme/app_theme.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/add_transaction_screen.dart';
import 'screens/transfer_screen.dart';
import 'widgets/preset_sheet.dart';
import 'services/notification_bootstrap.dart';
import 'services/quick_add_service.dart';
import 'services/workmanager_service.dart';
import 'services/auto_backup_service.dart';
import 'services/notification_service.dart';
import 'utils/service_localizations.dart';
import 'screens/sms_inbox_screen.dart';

/// Root navigator key so the "Quick Add Transaction" home screen widget can
/// push [AddTransactionScreen] on top of whatever's currently showing,
/// without MaterialApp itself needing to know about the widget at all.
/// See HOMESCREEN_WIDGET.md §4.2 — this is the "push on top of MainShell"
/// approach, preferred over swapping `home:` directly because it keeps
/// MainShell as the true root for every cold-start path (consistent with
/// CLAUDE.md §8) and back navigation "just works" via the normal
/// ExpensyRoute pop transition.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Awaiting [provider.load()] before [runApp] keeps the native LaunchTheme
/// window background (launch_background.xml) visible for the entire startup
/// duration.  Flutter only replaces it with the first Flutter frame, which is
/// already the real app — no intermediate loading screen, no double icon flash.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  CompositionRoot.init();
  try {
    await NotificationBootstrap.init();
    await WorkmanagerService.initialize();
    AutoBackupService.scheduleNext();
  } catch (e, stack) {
    debugPrint('Startup service initialization warning: $e\n$stack');
  }

  final provider = AppProvider();
  // Wire the assets view model before load(): load() assigns the asset list
  // through the provider's delegating setter, which needs the VM in place.
  CompositionRoot.initAssets(provider);
  final assetsVm = CompositionRoot.getIt<AssetsViewModel>();
  // Wire the presets view model before load(): load() assigns the preset
  // list through the provider's delegating setter, which needs the VM in place.
  CompositionRoot.initPresets(provider);
  final presetsVm = CompositionRoot.getIt<PresetsViewModel>();
  // Wire the goals view model before load(): load() assigns the
  // wishlist/savings-goal/contribution lists through the provider's
  // delegating setters, which need the VM in place.
  CompositionRoot.initGoals(provider);
  final goalsVm = CompositionRoot.getIt<GoalsViewModel>();
  // Wire the lended view model before load(): load() assigns the
  // lended-people / lended-money lists through the provider's delegating
  // setters, which need the VM in place.
  CompositionRoot.initLended(provider);
  final lendedVm = CompositionRoot.getIt<LendedViewModel>();
  // Wire the loans view model before load(): load() assigns the loans /
  // loan-payments lists through the provider's delegating setters, which
  // need the VM in place.
  CompositionRoot.initLoans(provider);
  final loansVm = CompositionRoot.getIt<LoansViewModel>();
  // Wire the categories view model before load(): load() assigns the
  // categories list through the provider's delegating setter, which needs
  // the VM in place.
  CompositionRoot.initCategories(provider);
  final categoriesVm = CompositionRoot.getIt<CategoriesViewModel>();
  // Wire the budgets view model before load(): load() assigns the budgets
  // list through the provider's delegating setter, which needs the VM in
  // place.
  CompositionRoot.initBudgets(provider);
  final budgetsVm = CompositionRoot.getIt<BudgetsViewModel>();
  // Wire the recurring view model before load(): load() assigns the
  // recurring list through the provider's delegating setter, which needs
  // the VM in place.
  CompositionRoot.initRecurring(provider);
  final recurringVm = CompositionRoot.getIt<RecurringViewModel>();
  // Wire the certificate view model before load(): load() assigns the
  // certificate list through the provider's delegating setter, which needs
  // the VM in place.
  CompositionRoot.initCertificate(provider);
  final certificateVm = CompositionRoot.getIt<CertificateViewModel>();
  // Wire the net-worth view model before load(): load() assigns the
  // snapshot list through the provider's delegating setter, which needs
  // the VM in place.
  CompositionRoot.initNetWorth(provider);
  final netWorthVm = CompositionRoot.getIt<NetWorthViewModel>();
  // Wire the transactions (ledger) view model before load(): load() assigns
  // the transactions/splits lists through the provider's delegating setters,
  // which need the VM in place.
  CompositionRoot.initTransactions(provider);
  final transactionsVm = CompositionRoot.getIt<TransactionsViewModel>();
  try {
    await provider.load(); // DB reads finish before Flutter draws anything
  } catch (e, stack) {
    debugPrint('Startup provider load warning: $e\n$stack');
  }

  // SMS import context: adapters bridge to the provider until the ledger
  // context is migrated (Phase 2).
  CompositionRoot.initSms(provider);
  final smsVm = CompositionRoot.getIt<SmsInboxViewModel>();
  await smsVm.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppProvider>.value(value: provider),
        ChangeNotifierProvider<AssetsViewModel>.value(value: assetsVm),
        ChangeNotifierProvider<PresetsViewModel>.value(value: presetsVm),
        ChangeNotifierProvider<GoalsViewModel>.value(value: goalsVm),
        ChangeNotifierProvider<LendedViewModel>.value(value: lendedVm),
        ChangeNotifierProvider<LoansViewModel>.value(value: loansVm),
        ChangeNotifierProvider<CategoriesViewModel>.value(value: categoriesVm),
        ChangeNotifierProvider<BudgetsViewModel>.value(value: budgetsVm),
        ChangeNotifierProvider<RecurringViewModel>.value(value: recurringVm),
        ChangeNotifierProvider<CertificateViewModel>.value(
            value: certificateVm),
        ChangeNotifierProvider<NetWorthViewModel>.value(value: netWorthVm),
        ChangeNotifierProvider<TransactionsViewModel>.value(
            value: transactionsVm),
        ChangeNotifierProvider<SmsInboxViewModel>.value(value: smsVm),
      ],
      child: const ExpensyApp(),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final payload = NotificationService.takePendingNotificationPayload();
    if (payload != null && payload.startsWith('sms:')) {
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => const SmsInboxScreen(),
        ),
      );
    }
  });
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final permissions = await smsVm.checkSmsPermissions();
    if (permissions.canScan) {
      unawaited(smsVm.scanSmsInbox(limit: 5000));
    }
    if (smsVm.smsLiveCaptureEnabled &&
        permissions.receive &&
        permissions.canScan) {
      unawaited(smsVm.startSmsLiveCapture());
    }
  });
}

class ExpensyApp extends StatefulWidget {
  const ExpensyApp({super.key});

  @override
  State<ExpensyApp> createState() => _ExpensyAppState();
}

class _ExpensyAppState extends State<ExpensyApp> {
  StreamSubscription<String?>? _quickAddSub;

  @override
  void initState() {
    super.initState();

    // Cold start: were we launched directly from a widget, shortcut, or quick tile?
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initialRoute = await QuickAddService.instance.getInitialRoute();
      if (initialRoute != null) {
        _handleRoute(initialRoute);
      }
    });

    // Warm start: app already alive in the background, shortcut/widget tapped again.
    _quickAddSub = QuickAddService.instance.routeStream.listen((route) {
      if (route != null) {
        _handleRoute(route);
      }
    });
  }

  void _handleRoute(String route) {
    final app = context.read<AppProvider>();
    if (!app.settings.onboarded) return;

    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;

    switch (route) {
      case QuickAddService.routeQuickAdd:
      case QuickAddService.routeExpense:
        nav.push(
          ExpensySlideUpRoute(
            builder: (_) => const AddTransactionScreen(initialType: 'expense'),
          ),
        );
        break;
      case QuickAddService.routeIncome:
        nav.push(
          ExpensySlideUpRoute(
            builder: (_) => const AddTransactionScreen(initialType: 'income'),
          ),
        );
        break;
      case QuickAddService.routeTransfer:
        nav.push(
          ExpensySlideUpRoute(
            builder: (_) => const TransferScreen(),
          ),
        );
        break;
      case QuickAddService.routePresets:
        final navContext = rootNavigatorKey.currentContext;
        if (navContext != null) {
          PresetSheet.show(navContext);
        }
        break;
    }
  }

  @override
  void dispose() {
    _quickAddSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch only the specific settings properties needed by MaterialApp.
    // This prevents the entire app from rebuilding when transactions, accounts, etc. change.
    final settingsRecord = context.select<AppProvider,
        (bool, String, String, String, String, bool, bool)>((app) {
      final s = app.settings;
      return (
        s.dynamicColorEnabled,
        s.languageCode,
        s.themeMode,
        s.themeSeed,
        s.appFont,
        s.amoledSurfaces,
        s.onboarded
      );
    });

    final usesDynamic = settingsRecord.$1;
    final languageCode = settingsRecord.$2;
    ServiceLocalizations.setLanguageCode(languageCode);
    final themeMode = settingsRecord.$3;
    final themeSeed = settingsRecord.$4;
    final appFont = settingsRecord.$5;
    final amoledSurfaces = settingsRecord.$6;
    final onboarded = settingsRecord.$7;

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          title: 'Finwick',
          navigatorKey: rootNavigatorKey,
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: languageCode == 'system' ? null : Locale(languageCode),
          themeMode: resolveThemeMode(themeMode),
          theme: buildTheme(
            seed: themeSeed,
            dark: false,
            appFont: appFont,
            dynamicScheme: usesDynamic ? lightDynamic : null,
          ),
          darkTheme: buildTheme(
            seed: themeSeed,
            dark: true,
            amoled: amoledSurfaces,
            appFont: appFont,
            dynamicScheme: usesDynamic ? darkDynamic : null,
          ),
          home: onboarded ? const MainShell() : const OnboardingScreen(),
        );
      },
    );
  }
}
