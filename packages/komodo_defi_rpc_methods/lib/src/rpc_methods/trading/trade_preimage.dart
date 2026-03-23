import 'package:komodo_defi_rpc_methods/src/common_structures/primitive/mm2_rational.dart';
import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:rational/rational.dart';

/// Request to calculate trade preimage (fees, validation)
class TradePreimageRequest
    extends BaseRequest<TradePreimageResponse, GeneralErrorResponse> {
  TradePreimageRequest({
    required String rpcPass,
    required this.base,
    required this.rel,
    required this.swapMethod,
    this.volume,
    this.max,
    this.price,
  }) : super(
         method: 'trade_preimage',
         rpcPass: rpcPass,
         mmrpc: RpcVersion.v2_0,
       );

  /// Base coin ticker for the potential trade
  final String base;

  /// Rel/quote coin ticker for the potential trade
  final String rel;

  /// Desired swap method (setprice, buy, sell)
  final SwapMethod swapMethod;

  /// Trade volume as a string numeric
  final String? volume;

  /// If true, compute preimage for "max" taker volume
  final bool? max;

  /// Optional price for maker trades
  final String? price;

  @override
  Map<String, dynamic> toJson() => super.toJson().deepMerge({
    'params': {
      'base': base,
      'rel': rel,
      'swap_method': swapMethod == SwapMethod.setPrice
          ? 'setprice'
          : swapMethod.name,
      if (volume != null) 'volume': volume,
      if (max != null) 'max': max,
      if (price != null) 'price': price,
    },
  });

  @override
  TradePreimageResponse parse(Map<String, dynamic> json) =>
      TradePreimageResponse.parse(json);
}

/// Response containing trade preimage details
class TradePreimageResponse extends BaseResponse {
  TradePreimageResponse({
    required super.mmrpc,
    required this.totalFees,
    this.baseCoinFee,
    this.relCoinFee,
    this.takerFee,
    this.feeToSendTakerFee,
  });

  factory TradePreimageResponse.parse(JsonMap json) {
    final result = json.value<JsonMap>('result');

    return TradePreimageResponse(
      mmrpc: json.value<String>('mmrpc'),
      baseCoinFee: result.containsKey('base_coin_fee')
          ? PreimageCoinFee.fromJson(result.value<JsonMap>('base_coin_fee'))
          : null,
      relCoinFee: result.containsKey('rel_coin_fee')
          ? PreimageCoinFee.fromJson(result.value<JsonMap>('rel_coin_fee'))
          : null,
      takerFee: result.containsKey('taker_fee')
          ? PreimageCoinFee.fromJson(result.value<JsonMap>('taker_fee'))
          : null,
      feeToSendTakerFee: result.containsKey('fee_to_send_taker_fee')
          ? PreimageCoinFee.fromJson(
              result.value<JsonMap>('fee_to_send_taker_fee'),
            )
          : null,
      totalFees: (result.valueOrNull<JsonList>('total_fees') ?? [])
          .map(PreimageTotalFee.fromJson)
          .toList(),
    );
  }

  /// Estimated fee for the base coin leg
  final PreimageCoinFee? baseCoinFee;

  /// Estimated fee for the rel/quote coin leg
  final PreimageCoinFee? relCoinFee;

  /// Estimated taker fee, if applicable
  final PreimageCoinFee? takerFee;

  /// Fee required to send the taker fee, if applicable
  final PreimageCoinFee? feeToSendTakerFee;

  /// Aggregated list of total fees across involved coins
  final List<PreimageTotalFee> totalFees;

  @override
  Map<String, dynamic> toJson() => {
    'mmrpc': mmrpc,
    'result': {
      if (baseCoinFee != null) 'base_coin_fee': baseCoinFee!.toJson(),
      if (relCoinFee != null) 'rel_coin_fee': relCoinFee!.toJson(),
      if (takerFee != null) 'taker_fee': takerFee!.toJson(),
      if (feeToSendTakerFee != null)
        'fee_to_send_taker_fee': feeToSendTakerFee!.toJson(),
      'total_fees': totalFees.map((e) => e.toJson()).toList(),
    },
  };
}

/// Signed big integer parts used by MM2 rational encoding
const _mm2LimbBase = 1 << 32; // 2^32

BigInt _bigIntFromMm2Json(List<dynamic> json) {
  final sign = (json[0] as num).toInt();
  final limbs = (json[1] as List).map((limb) => (limb as num).toInt());
  if (sign == 0) return BigInt.zero;
  var value = BigInt.zero;
  var multiplier = BigInt.one;
  for (final limb in limbs) {
    value += BigInt.from(limb) * multiplier;
    multiplier *= BigInt.from(_mm2LimbBase);
  }
  return sign < 0 ? -value : value;
}

List<dynamic> _bigIntToMm2Json(BigInt value) {
  if (value == BigInt.zero) {
    return [
      0,
      <int>[0],
    ];
  }
  final sign = value.isNegative ? -1 : 1;
  var x = value.abs();
  final limbs = <int>[];
  final base = BigInt.from(_mm2LimbBase);
  while (x > BigInt.zero) {
    final q = x ~/ base;
    final r = x - q * base;
    limbs.add(r.toInt());
    x = q;
  }
  if (limbs.isEmpty) limbs.add(0);
  return [sign, limbs];
}

Rational _rationalFromMm2(List<dynamic> json) {
  final numJson = (json[0] as List).cast<dynamic>();
  final denJson = (json[1] as List).cast<dynamic>();
  final num = _bigIntFromMm2Json(numJson);
  final den = _bigIntFromMm2Json(denJson);
  if (den == BigInt.zero) {
    throw const FormatException('Denominator cannot be zero in MM2 rational');
  }
  return Rational(num, den);
}

List<dynamic> _rationalToMm2(Rational r) {
  return [_bigIntToMm2Json(r.numerator), _bigIntToMm2Json(r.denominator)];
}

class PreimageCoinFee {
  PreimageCoinFee({
    required this.coin,
    required this.amount,
    required this.amountFraction,
    required this.amountRat,
    required this.paidFromTradingVol,
  });

  factory PreimageCoinFee.fromJson(JsonMap json) {
    return PreimageCoinFee(
      coin: json.value<String>('coin'),
      amount: json.value<String>('amount'),
      amountFraction: Fraction.fromJson(json.value<JsonMap>('amount_fraction')),
      amountRat: rationalFromMm2(json.value<List<dynamic>>('amount_rat')),
      paidFromTradingVol: json.value<bool>('paid_from_trading_vol'),
    );
  }

  /// Coin ticker for which the fee applies
  final String coin;

  /// Fee amount as a string numeric
  final String amount;

  /// Fractional representation of the fee
  final Fraction amountFraction;

  /// Rational form of the amount (as returned by API)
  final Rational amountRat;

  /// True if the fee is deducted from the trading volume
  final bool paidFromTradingVol;

  Map<String, dynamic> toJson() => {
    'coin': coin,
    'amount': amount,
    'amount_fraction': amountFraction.toJson(),
    'amount_rat': rationalToMm2(amountRat),
    'paid_from_trading_vol': paidFromTradingVol,
  };
}

class PreimageTotalFee {
  PreimageTotalFee({
    required this.coin,
    required this.amount,
    required this.amountFraction,
    required this.amountRat,
    required this.requiredBalance,
    required this.requiredBalanceFraction,
    required this.requiredBalanceRat,
  });

  factory PreimageTotalFee.fromJson(JsonMap json) {
    return PreimageTotalFee(
      coin: json.value<String>('coin'),
      amount: json.value<String>('amount'),
      amountFraction: Fraction.fromJson(json.value<JsonMap>('amount_fraction')),
      amountRat: rationalFromMm2(json.value<List<dynamic>>('amount_rat')),
      requiredBalance: json.value<String>('required_balance'),
      requiredBalanceFraction: Fraction.fromJson(
        json.value<JsonMap>('required_balance_fraction'),
      ),
      requiredBalanceRat: rationalFromMm2(
        json.value<List<dynamic>>('required_balance_rat'),
      ),
    );
  }

  /// Coin ticker for which the total fee summary applies
  final String coin;

  /// Total fee amount as a string numeric
  final String amount;

  /// Fractional representation of the amount
  final Fraction amountFraction;

  /// Rational representation of the amount (API-specific)
  final Rational amountRat;

  /// Required balance to perform the trade
  final String requiredBalance;

  /// Fractional representation of the required balance
  final Fraction requiredBalanceFraction;

  /// Rational representation of the required balance
  final Rational requiredBalanceRat;

  Map<String, dynamic> toJson() => {
    'coin': coin,
    'amount': amount,
    'amount_fraction': amountFraction.toJson(),
    'amount_rat': rationalToMm2(amountRat),
    'required_balance': requiredBalance,
    'required_balance_fraction': requiredBalanceFraction.toJson(),
    'required_balance_rat': rationalToMm2(requiredBalanceRat),
  };
}
