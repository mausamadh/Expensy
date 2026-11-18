// One shared date parser for template DATE fields (parseTemplateDate) and
// fallback body scans (parseFlexibleDate). Unparsable input returns null so
// the caller keeps the SMS timestamp. All results are UTC.

class MessageDateParser {
  // Sent messages show years as 2026 or 26 and month names in any case
  // ("08 SEP 2026"), so several date shapes share one field.
  static DateTime? parseTemplateDate(String value) {
    final v = value.trim();
    final dmy4 = _templateDmy4.firstMatch(v);
    if (dmy4 != null) {
      return dateAtMidnight(
          int.parse(dmy4.group(3)!), int.parse(dmy4.group(2)!), int.parse(dmy4.group(1)!));
    }
    final dmy2 = _templateDmy2.firstMatch(v);
    if (dmy2 != null) {
      return dateAtMidnight(
          2000 + int.parse(dmy2.group(3)!),
          int.parse(dmy2.group(2)!),
          int.parse(dmy2.group(1)!));
    }
    final textual = _templateTextual.firstMatch(v);
    if (textual != null) {
      final month = monthFromName(textual.group(2)!);
      if (month == null) return null;
      return dateAtMidnight(
          int.parse(textual.group(3)!), month, int.parse(textual.group(1)!));
    }
    final iso = _templateIso.firstMatch(v);
    if (iso != null) {
      return dateAtMidnight(
          int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
    }
    return null;
  }

  // ISO, numeric d/M/yyyy resolved with preferMonthFirst, or textual
  // "MMM d, yyyy" with a bounded scan after the date for a 12-hour time.
  static DateTime? parseFlexibleDate(String value, bool preferMonthFirst) {
    final iso = _isoDate.firstMatch(value);
    final numeric = iso == null ? _numericDate.firstMatch(value) : null;
    final textual =
        (iso == null && numeric == null) ? _textualDate.firstMatch(value) : null;

    DateTime? date;
    int? afterDate;
    if (iso != null) {
      date = _parseIso(iso.group(1)!);
      afterDate = iso.end;
    } else if (numeric != null) {
      date = resolvedNumericDate(numeric, preferMonthFirst);
      afterDate = numeric.end;
    } else if (textual != null) {
      final month = monthFromName(textual.group(1)!);
      if (month != null) {
        date = _safeDate(
            int.parse(textual.group(3)!), month, int.parse(textual.group(2)!));
      }
      afterDate = textual.end;
    }
    if (date == null || afterDate == null) return null;

    final time = trailingTime(value, afterDate);
    return _safeDate(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 0,
        time?.minute ?? 0);
  }

  static final _templateDmy4 = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$');
  static final _templateDmy2 = RegExp(r'^(\d{2})/(\d{2})/(\d{2})$');
  static final _templateTextual = RegExp(r'^(\d{2})\s+([A-Za-z]{3,9}),?\s+(\d{4})$');
  static final _templateIso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  static final _isoDate = RegExp(r'\b(\d{4}-\d{2}-\d{2})\b');
  static final _numericDate = RegExp(r'\b(\d{1,2})/(\d{1,2})/(\d{4})\b');
  static final _textualDate = RegExp(r'\b([A-Za-z]{3,9})\s+(\d{1,2}),\s*(\d{4})\b');
  static final _twelveHourTime =
      RegExp(r'(\d{1,2}):(\d{2})\s*([AP])\.?M\.?', caseSensitive: false);

  static int? monthFromName(String name) {
    final key = name.toLowerCase();
    return _monthNumbers[key] ?? _fullMonthNames[key];
  }

  static const _monthNumbers = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static const _fullMonthNames = {
    'january': 1, 'february': 2, 'march': 3, 'april': 4, 'june': 6,
    'july': 7, 'august': 8, 'september': 9, 'october': 10,
    'november': 11, 'december': 12,
  };

  // A first component above 12 can only be the day, whatever the seeded
  // country convention says.
  static DateTime? resolvedNumericDate(RegExpMatch match, bool preferMonthFirst) {
    final first = int.parse(match.group(1)!);
    final second = int.parse(match.group(2)!);
    final year = int.parse(match.group(3)!);
    final monthFirst = preferMonthFirst && first <= 12;
    final month = monthFirst ? first : second;
    final day = monthFirst ? second : first;
    return _safeDate(year, month, day);
  }

  // Bounded scan right after the date for an optional 12-hour time.
  static _Time? trailingTime(String value, int fromIndex) {
    if (fromIndex < 0) return null;
    final window =
        value.substring(fromIndex, fromIndex + 25 > value.length ? value.length : fromIndex + 25);
    final match = _twelveHourTime.firstMatch(window);
    if (match == null) return null;
    var hour = int.parse(match.group(1)!) % 12;
    if (match.group(3)!.toUpperCase() == 'P') hour += 12;
    final minute = int.parse(match.group(2)!);
    if (minute > 59) return null;
    return _Time(hour, minute);
  }

  static DateTime? _parseIso(String s) {
    final parts = s.split('-');
    if (parts.length != 3) return null;
    return _safeDate(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  }

  static DateTime? dateAtMidnight(int year, int month, int day) =>
      _safeDate(year, month, day);

  static DateTime? _safeDate(int year, int month, int day,
      [int hour = 0, int minute = 0]) {
    // Dart's DateTime normalizes out-of-range fields (month 31 rolls over)
    // instead of throwing, so validate explicitly like Kotlin's LocalDate.
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    try {
      final d = DateTime.utc(year, month, day, hour, minute);
      if (d.month != month || d.day != day) return null;
      return d;
    } catch (_) {
      return null;
    }
  }
}

class _Time {
  final int hour;
  final int minute;
  _Time(this.hour, this.minute);
}
