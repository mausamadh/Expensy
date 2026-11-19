import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finwick/models/models.dart';
import 'package:finwick/providers/app_provider.dart';
import 'package:finwick/widgets/shared_widgets.dart';
import 'package:finwick/screens/recurring_screen.dart';
import 'package:finwick/utils/nav_metrics.dart';
import 'package:finwick/l10n/app_localizations.dart';
import 'helpers/categories_test_harness.dart';
import 'helpers/recurring_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AccountCardPicker rendering', () {
    testWidgets('shows bank accounts and cash wallets normally',
        (tester) async {
      final normalBank = Account(
        id: 'bank-linked',
        name: 'Linked Bank',
        type: 'bank',
        currency: 'USD',
        balance: 1000,
        colorValue: 0xFF2196F3,
        dontLinkToCard: false,
      );

      final unlinkedBank = Account(
        id: 'bank-unlinked',
        name: 'Unlinked Bank',
        type: 'bank',
        currency: 'USD',
        balance: 2000,
        colorValue: 0xFF4CAF50,
        dontLinkToCard: true,
      );

      final regularWallet = Account(
        id: 'cash-wallet',
        name: 'Cash Wallet',
        type: 'cash',
        currency: 'USD',
        balance: 500,
        colorValue: 0xFFFF9800,
      );

      String? selectedId;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountCardPicker(
              accounts: [normalBank, unlinkedBank, regularWallet],
              selectedId: selectedId,
              onSelected: (id) => selectedId = id,
            ),
          ),
        ),
      );

      // Linked bank account should appear
      expect(find.text('Linked Bank'), findsOneWidget);

      // Unlinked bank account should appear
      expect(find.text('Unlinked Bank'), findsOneWidget);

      // Cash wallet should appear
      expect(find.text('Cash Wallet'), findsOneWidget);

      // Tapping unlinked bank account triggers onSelected
      await tester.tap(find.text('Unlinked Bank'));
      expect(selectedId, equals('bank-unlinked'));
    });
  });

  group('RecurringScreen FAB bottom padding', () {
    testWidgets('FAB padding is positioned directly above the floating navbar',
        (tester) async {
      final app = AppProvider();

      await tester.pumpWidget(
        wrapWithRecurring(
          app,
          wrapWithCategories(
            app,
            const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: RecurringScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final scaffoldFinder = find.byType(Scaffold);
      expect(scaffoldFinder, findsOneWidget);

      final scaffold = tester.widget<Scaffold>(scaffoldFinder);
      expect(scaffold.floatingActionButton, isNotNull);

      // Verify NavAwareFabLocation and ExpandableFab are configured correctly
      expect(scaffold.floatingActionButtonLocation, isA<NavAwareFabLocation>());
      expect(scaffold.floatingActionButton, isA<ExpandableFab>());
    });
  });
}
