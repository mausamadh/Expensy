import 'package:finwick/domain/shared/date_range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DateRange', () {
    test('ofDates normalizes to day boundaries', () {
      final r = DateRange.ofDates(
        DateTime(2026, 1, 1, 23, 59),
        DateTime(2026, 1, 31, 0, 1),
      );
      expect(r.start, DateTime(2026, 1, 1));
      expect(r.end, DateTime(2026, 1, 31));
      expect(r.dayCount, 31);
    });

    test('contains is inclusive on both ends', () {
      final r = DateRange.ofDates(DateTime(2026, 1, 1), DateTime(2026, 1, 3));
      expect(r.contains(DateTime(2026, 1, 1, 0, 0)), isTrue);
      expect(r.contains(DateTime(2026, 1, 3, 23, 59)), isTrue);
      expect(r.contains(DateTime(2026, 1, 4, 0, 0)), isFalse);
      expect(r.contains(DateTime(2025, 12, 31, 23, 59)), isFalse);
    });

    test('invalid range contains nothing', () {
      final r = DateRange(DateTime(2026, 2, 1), DateTime(2026, 1, 1));
      expect(r.isValid, isFalse);
      expect(r.contains(DateTime(2026, 1, 15)), isFalse);
    });

    test('overlaps detects touching and disjoint ranges', () {
      final jan = DateRange.ofDates(DateTime(2026, 1, 1), DateTime(2026, 1, 31));
      final feb = DateRange.ofDates(DateTime(2026, 2, 1), DateTime(2026, 2, 28));
      final janMid = DateRange.ofDates(DateTime(2026, 1, 15), DateTime(2026, 1, 20));
      expect(jan.overlaps(feb), isFalse);
      expect(jan.overlaps(janMid), isTrue);
      expect(jan.overlaps(jan), isTrue);
    });

    test('equality is value-based', () {
      final a = DateRange.ofDates(DateTime(2026, 1, 1, 5), DateTime(2026, 1, 2, 20));
      final b = DateRange(DateTime(2026, 1, 1), DateTime(2026, 1, 2));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
