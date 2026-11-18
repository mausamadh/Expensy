import 'iso4217.dart';

// Shared recognition set for currency tokens: the active ISO codes, the
// curated symbols, and the English word forms. Extending symbol or word
// coverage means adding here and mapping the token in currencyCodeFor; code
// coverage derives from Iso4217 so a new active code needs no list here.

// Fund and special drawing codes scale amounts in Iso4217 but never name a
// user's money, so detection excludes them.
const _fundSpecialCodes = {
  'BOV', 'CHE', 'CHW', 'CLF', 'COU', 'MXV', 'UYI', 'UYW', 'XDR',
};

// ISO codes whose lowercase form is a common English word ("top", "rub"):
// they count only written in uppercase, or ordinary message words would read
// as currency.
const _uppercaseOnlyCodes = {
  'ALL', 'BOB', 'COP', 'CRC', 'CUP', 'GEL', 'MAD', 'MOP',
  'PEN', 'RUB', 'SOS', 'TOP', 'TRY',
};

// Codes need a left word boundary ("POKES" never reads as KES) and a right
// edge that accepts a digit or a boundary so attached amounts keep working
// ("KES500").
final _currencyCodeAlternation =
    r'\b(?:' + _currencyCodeList.join('|') + r')(?=\d|\b)';

final _currencyCodeList = () {
  final codes = Iso4217.minorUnitExponents.keys
      .toSet()
      .difference(_fundSpecialCodes)
      .toList()
    ..sort();
  return codes;
}();

const _currencySymbolAlternation = r'\$|₦|₹|£|€';

// Word tokens need boundaries so they never fire inside unrelated words
// ("grand", "brand").
const currencyWordAlternation =
    r'\b(?:shillings?|dollars?|naira|rupees?|euros?|pounds?|cedis?|rand|birr)\b';

final allCurrencyTokens =
    'KShs?|$_currencyCodeAlternation|$_currencySymbolAlternation|$currencyWordAlternation';

final currencyTokens = RegExp('($allCurrencyTokens)\\.?\\s*', caseSensitive: false);

// Collision codes ("top", "rub") are money only in their exact uppercase
// spelling; any other casing is an ordinary word. Symbols and word forms
// always pass.
bool isRecognizedCurrencyToken(String token) {
  final code = token.toUpperCase();
  return !_uppercaseOnlyCodes.contains(code) || token == code;
}

// "Space" covers the visible space plus the Unicode spaces phones render for
// one another: no-break, thin, and narrow no-break.
const _spaceClass = ' \u00A0\u2009\u202F';

// A number run keeps the separators digits carry, including dangling ones,
// so shapes matching no grammar row (",5", "1,") classify as invalid.
final _numberRun = RegExp(r'-?[\d.,]*\d[\d.,]*');

final _spaceGrouped =
    RegExp('^-?\\d{1,3}(?:[$_spaceClass]\\d{3})+(?:,\\d{1,2})?\$');
final _dotGroupedCommaDecimal = RegExp(r'^\d{1,3}(?:\.\d{3})*,\d+$');
final _commaGroupedDotDecimal = RegExp(r'^\d{1,3}(?:,\d{3})+\.\d+$');
final _lakhGroupedDotDecimal = RegExp(r'^\d{1,2}(?:,\d{2})*,\d{3}\.\d+$');
final _commaGrouped = RegExp(r'^\d{1,2}(?:,\d{2})*,\d{3}$|^\d{1,3}(?:,\d{3})+$');
final _commaDecimal = RegExp(r'^\d+,\d{1,2}$');
final _dotGrouped = RegExp(r'^\d{1,3}(?:\.\d{3}){2,}$');
final _dotDecimal = RegExp(r'^\d+(?:\.\d+)?$');
final _plainDigits = RegExp(r'^\d+$');

// ISO code of the last currency token in the value, or null when none.
String? detectCurrencyCode(String value) {
  String? last;
  for (final m in currencyTokens.allMatches(value)) {
    final token = m.group(1)!;
    if (isRecognizedCurrencyToken(token)) last = token;
  }
  return last == null ? null : currencyCodeFor(last);
}

// Parses the amount text into minor units scaled to the currency exponent.
// The amount is the number following the LAST currency token in the value;
// values matching no locale shape return null.
int? parseAmountToMinorUnits(String value, int exponent) {
  if (value.trim().isEmpty) return null;
  String? afterToken;
  for (final m in currencyTokens.allMatches(value)) {
    afterToken = value.substring(m.end);
  }
  afterToken ??= value;
  final trimmed = afterToken
      .replaceFirst(RegExp('^[ \u00A0\u2009\u202F\t\n\r]+'), '')
      .replaceFirst(RegExp('[ \u00A0\u2009\u202F\t\n\r]+\$'), '');
  if (_spaceGrouped.hasMatch(trimmed)) {
    final negative = trimmed.startsWith('-');
    final body = negative ? trimmed.substring(1) : trimmed;
    final integerPart =
        body.split(',').first.replaceAll(RegExp('[$_spaceClass]'), '');
    final decimalPart = body.contains(',') ? body.split(',').last : '';
    return scaleToMinorUnits(integerPart, decimalPart, exponent, negative);
  }
  String? number;
  for (final m in _numberRun.allMatches(afterToken)) {
    number = m.group(0);
  }
  if (number == null) return null;
  return numberToMinorUnits(number, exponent);
}

// ISO code for a recognized currency token; unknown tokens pass through
// uppercased so plain ISO codes map to themselves.
String currencyCodeFor(String token) {
  switch (token.toUpperCase()) {
    case 'KSH':
    case 'KSHS':
    case 'SHILLING':
    case 'SHILLINGS':
      return 'KES';
    case r'$':
    case 'DOLLAR':
    case 'DOLLARS':
      return 'USD';
    case '₦':
    case 'NAIRA':
      return 'NGN';
    case '₹':
    case 'RUPEE':
    case 'RUPEES':
      return 'INR';
    case '€':
    case 'EURO':
    case 'EUROS':
      return 'EUR';
    case '£':
    case 'POUND':
    case 'POUNDS':
      return 'GBP';
    case 'CEDI':
    case 'CEDIS':
      return 'GHS';
    case 'RAND':
      return 'ZAR';
    case 'BIRR':
      return 'ETB';
    default:
      return token.toUpperCase();
  }
}

int? numberToMinorUnits(String raw, int exponent) {
  var s = raw;
  final negative = s.startsWith('-');
  if (negative) s = s.substring(1);
  if (s.isEmpty || s[0] == '.' || s[0] == ',') return null;

  String integerPart;
  String decimalPart;
  if (s.contains('.') && s.contains(',')) {
    final decimalSep = s.lastIndexOf(',') > s.lastIndexOf('.') ? ',' : '.';
    final groupingSep = decimalSep == ',' ? '.' : ',';
    final shaped = groupingSep == '.'
        ? _dotGroupedCommaDecimal.hasMatch(s)
        : (_commaGroupedDotDecimal.hasMatch(s) ||
            _lakhGroupedDotDecimal.hasMatch(s));
    if (!shaped) return null;
    final sepIdx = s.indexOf(decimalSep);
    integerPart = s.substring(0, sepIdx).replaceAll(groupingSep, '');
    decimalPart = s.substring(sepIdx + 1);
  } else if (s.contains(',')) {
    if (_commaGrouped.hasMatch(s)) {
      integerPart = s.replaceAll(',', '');
      decimalPart = '';
    } else if (_commaDecimal.hasMatch(s)) {
      final sepIdx = s.indexOf(',');
      integerPart = s.substring(0, sepIdx);
      decimalPart = s.substring(sepIdx + 1);
    } else {
      return null;
    }
  } else if (s.contains('.')) {
    if (_dotGrouped.hasMatch(s)) {
      integerPart = s.replaceAll('.', '');
      decimalPart = '';
    } else if (_dotDecimal.hasMatch(s)) {
      final sepIdx = s.indexOf('.');
      integerPart = s.substring(0, sepIdx);
      decimalPart = s.substring(sepIdx + 1);
    } else {
      return null;
    }
  } else if (_plainDigits.hasMatch(s)) {
    integerPart = s;
    decimalPart = '';
  } else {
    return null;
  }
  return scaleToMinorUnits(integerPart, decimalPart, exponent, negative);
}

// Scales the digit string to the currency exponent: fewer decimals append
// zeros, more decimals round half away from zero. Sign applies last.
int? scaleToMinorUnits(
    String integerPart, String decimalPart, int exponent, bool negative) {
  var digits = (integerPart + decimalPart).replaceFirst(RegExp('^0+'), '');
  if (digits.isEmpty) digits = '0';
  final places = decimalPart.length;
  final String scaled;
  if (places <= exponent) {
    scaled = digits + '0' * (exponent - places);
  } else {
    final drop = places - exponent;
    final kept = drop >= digits.length ? '0' : digits.substring(0, digits.length - drop);
    final removed = drop >= digits.length ? digits : digits.substring(digits.length - drop);
    final base = int.tryParse(kept);
    if (base == null) return null;
    // Removed fraction rounds up at exactly half of the kept scale.
    final half = '5' + '0' * (drop - 1);
    scaled = (removed.padLeft(drop, '0').compareTo(half) >= 0 ? base + 1 : base).toString();
  }
  final magnitude = int.tryParse(scaled);
  if (magnitude == null) return null;
  return negative ? -magnitude : magnitude;
}
