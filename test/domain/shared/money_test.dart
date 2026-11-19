import 'package:finwick/domain/shared/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money', () {
    test('zero factory and predicates', () {
      final m = Money.zero('NPR');
      expect(m.minorUnits, 0);
      expect(m.currencyCode, 'NPR');
      expect(m.isZero, isTrue);
      expect(m.isPositive, isFalse);
      expect(m.isNegative, isFalse);
    });

    test('add/subtract in same currency', () {
      final a = Money(1500, 'NPR');
      final b = Money(250, 'NPR');
      expect(a.add(b), Money(1750, 'NPR'));
      expect(a.subtract(b), Money(1250, 'NPR'));
    });

    test('cross-currency arithmetic throws', () {
      expect(() => Money(1, 'NPR').add(Money(1, 'USD')),
          throwsArgumentError);
      expect(() => Money(1, 'NPR').subtract(Money(1, 'USD')),
          throwsArgumentError);
    });

    test('negate and times', () {
      final m = Money(100, 'NPR');
      expect(m.negate(), Money(-100, 'NPR'));
      expect(m.times(3), Money(300, 'NPR'));
      expect(m.times(0), Money.zero('NPR'));
    });

    test('equality is value-based', () {
      expect(Money(100, 'NPR'), Money(100, 'NPR'));
      expect(Money(100, 'NPR').hashCode, Money(100, 'NPR').hashCode);
      expect(Money(100, 'NPR') == Money(100, 'USD'), isFalse);
    });

    test('immutability: operations return new instances', () {
      final a = Money(100, 'NPR');
      final b = a.add(Money(50, 'NPR'));
      expect(a.minorUnits, 100);
      expect(b.minorUnits, 150);
    });
  });
}
