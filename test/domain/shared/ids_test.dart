import 'package:finwick/domain/shared/ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TypedId', () {
    test('equality is by value, not identity', () {
      expect(const AccountId('a1'), const AccountId('a1'));
      expect(const AccountId('a1').hashCode, const AccountId('a1').hashCode);
      expect(const AccountId('a1') == const AccountId('a2'), isFalse);
    });

    test('toString returns the raw value', () {
      expect(const TransactionId('t-123').toString(), 't-123');
    });

    test('all id types share value semantics', () {
      expect(const CategoryId('c'), const CategoryId('c'));
      expect(const BudgetId('b'), const BudgetId('b'));
      expect(const RecurringId('r'), const RecurringId('r'));
      expect(const SmsInboxItemId('s'), const SmsInboxItemId('s'));
    });
  });
}
