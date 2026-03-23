import 'package:rational/rational.dart';

/// Signed big integer parts used by MM2 rational encoding
const int mm2LimbBase = 4294967296; // 2^32

BigInt bigIntFromMm2Json(List<dynamic> json) {
  final sign = (json[0] as num).toInt();
  final limbs = (json[1] as List).map((limb) => (limb as num).toInt());
  if (sign == 0) return BigInt.zero;
  var value = BigInt.zero;
  var multiplier = BigInt.one;
  for (final limb in limbs) {
    value += BigInt.from(limb) * multiplier;
    multiplier *= BigInt.from(mm2LimbBase);
  }
  return sign < 0 ? -value : value;
}

List<dynamic> bigIntToMm2Json(BigInt value) {
  if (value == BigInt.zero) {
    return [
      0,
      <int>[0],
    ];
  }
  final sign = value.isNegative ? -1 : 1;
  var x = value.abs();
  final limbs = <int>[];
  final base = BigInt.from(mm2LimbBase);
  while (x > BigInt.zero) {
    final q = x ~/ base;
    final r = x - q * base;
    limbs.add(r.toInt());
    x = q;
  }
  if (limbs.isEmpty) limbs.add(0);
  return [sign, limbs];
}

Rational rationalFromMm2(List<dynamic> json) {
  final numJson = (json[0] as List).cast<dynamic>();
  final denJson = (json[1] as List).cast<dynamic>();
  final num = bigIntFromMm2Json(numJson);
  final den = bigIntFromMm2Json(denJson);
  if (den == BigInt.zero) {
    throw const FormatException('Denominator cannot be zero in MM2 rational');
  }
  return Rational(num, den);
}

List<dynamic> rationalToMm2(Rational r) {
  return [bigIntToMm2Json(r.numerator), bigIntToMm2Json(r.denominator)];
}
