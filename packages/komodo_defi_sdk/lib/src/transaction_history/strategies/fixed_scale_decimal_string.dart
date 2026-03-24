/// Converts an integer or digit string [raw] into a fixed-scale decimal string
/// by inserting the decimal point [decimals] places from the right.
///
/// Avoids `decimal` package division, which can stringify as rational
/// fractions (`n/d`) that do not round-trip through `Decimal.parse`.
String fixedScaleIntToDecimalString(int raw, int decimals) {
  if (decimals <= 0) return raw.toString();
  return fixedScaleDigitStringToDecimalString(raw.toString(), decimals);
}

/// Same as [fixedScaleIntToDecimalString] but for arbitrary-length integer
/// strings (e.g. TRC-20 `value` fields).
String fixedScaleBigIntStringToDecimalString(String raw, int decimals) {
  if (decimals <= 0) return raw;
  return fixedScaleDigitStringToDecimalString(raw, decimals);
}

/// Core implementation shared by [fixedScaleIntToDecimalString] and
/// [fixedScaleBigIntStringToDecimalString].
String fixedScaleDigitStringToDecimalString(String raw, int decimals) {
  final negative = raw.startsWith('-');
  var digits = negative ? raw.substring(1) : raw;
  digits = digits.padLeft(decimals + 1, '0');
  final intPart = digits.substring(0, digits.length - decimals);
  final fracPart = digits.substring(digits.length - decimals);
  final trimmedFrac = fracPart.replaceFirst(RegExp(r'0+$'), '');
  final sign = negative ? '-' : '';
  if (trimmedFrac.isEmpty) return '$sign$intPart';
  return '$sign$intPart.$trimmedFrac';
}
