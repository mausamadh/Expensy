/// An inclusive range of calendar days.
///
/// Both bounds are normalized to midnight of their day, so a range from
/// 2026-01-01 to 2026-01-31 contains every instant on those 31 days.
class DateRange {
  final DateTime start;
  final DateTime end;

  const DateRange(this.start, this.end);

  /// Builds a range from arbitrary datetimes, normalizing to day boundaries.
  factory DateRange.ofDates(DateTime start, DateTime end) {
    return DateRange(
      DateTime(start.year, start.month, start.day),
      DateTime(end.year, end.month, end.day),
    );
  }

  bool get isValid => !start.isAfter(end);

  bool contains(DateTime moment) {
    if (!isValid) return false;
    final day = DateTime(moment.year, moment.month, moment.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  bool overlaps(DateRange other) {
    if (!isValid || !other.isValid) return false;
    return !start.isAfter(other.end) && !other.start.isAfter(end);
  }

  /// Number of days in the range, inclusive.
  int get dayCount => end.difference(start).inDays + 1;

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DateRange($start .. $end)';
}
