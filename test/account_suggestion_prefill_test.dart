import 'package:finwick/l10n/app_localizations.dart';
import 'package:finwick/providers/app_provider.dart';
import 'package:finwick/screens/accounts_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<void> _openSuggestedSheet(
  WidgetTester tester, {
  required String name,
  required String type,
  required bool isCard,
}) async {
  final provider = AppProvider();
  await tester.pumpWidget(
    ChangeNotifierProvider<AppProvider>.value(
      value: provider,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => AccountsScreen.openSheet(
                context,
                isCard: isCard,
                initialName: name,
                initialType: type,
              ),
              child: const Text('Open suggestion'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open suggestion'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('suggested bank name and type are prefilled', (tester) async {
    await _openSuggestedSheet(
      tester,
      name: 'Nabil Bank',
      type: 'bank',
      isCard: false,
    );

    final nameField = tester.widget<TextField>(find.byType(TextField).first);
    expect(nameField.controller?.text, 'Nabil Bank');

    final bankFinder = find.text('Bank');
    final bankChip = find.ancestor(
      of: bankFinder,
      matching: find.byType(AnimatedContainer),
    );
    final decoration = tester
        .widget<AnimatedContainer>(bankChip.first)
        .decoration! as BoxDecoration;
    expect(
      decoration.color,
      Theme.of(tester.element(bankFinder)).colorScheme.primary,
    );
  });

  testWidgets('suggested debit-card name and type are prefilled',
      (tester) async {
    await _openSuggestedSheet(
      tester,
      name: 'Example Debit Card',
      type: 'debit',
      isCard: true,
    );

    final nameField = tester.widget<TextField>(find.byType(TextField).first);
    expect(nameField.controller?.text, 'Example Debit Card');

    final debitFinder = find.text('Debit Card');
    final debitChip = find.ancestor(
      of: debitFinder,
      matching: find.byType(AnimatedContainer),
    );
    final decoration = tester
        .widget<AnimatedContainer>(debitChip.first)
        .decoration! as BoxDecoration;
    expect(
      decoration.color,
      Theme.of(tester.element(debitFinder)).colorScheme.primary,
    );
  });
}
