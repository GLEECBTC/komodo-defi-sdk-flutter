import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:rational/rational.dart';

/// Request to get the maximum taker volume for a coin/pair.
///
/// Calculates how much of `coin` can be traded as a taker when trading against
/// the optional `trade_with` counter coin, taking balance, fees and dust limits
/// into account.
///
/// KDF serves `max_taker_vol` only on its legacy dispatcher, which it reaches
/// only when `mmrpc` is absent, and only for an activated coin.
class MaxTakerVolumeRequest
    extends BaseRequest<MaxTakerVolumeResponse, GeneralErrorResponse> {
  MaxTakerVolumeRequest({
    required String rpcPass,
    required this.coin,
    this.tradeWith,
  }) : super(method: 'max_taker_vol', rpcPass: rpcPass, mmrpc: null);

  /// Coin ticker to compute max taker volume for
  final String coin;

  /// Optional counter coin to trade against (`trade_with` in the API).
  ///
  /// This tells the API which other coin you intend to trade `coin` with, so
  /// the maximum volume is computed for that specific pair. If omitted, it
  /// defaults to the same value as `coin` (API default).
  final String? tradeWith;

  @override
  Map<String, dynamic> toJson() => super.toJson().deepMerge({
    'coin': coin,
    if (tradeWith != null) 'trade_with': tradeWith,
  });

  @override
  MaxTakerVolumeResponse parse(Map<String, dynamic> json) =>
      MaxTakerVolumeResponse.parse(json);
}

/// Response with maximum taker volume for the requested coin/pair.
class MaxTakerVolumeResponse extends BaseResponse {
  MaxTakerVolumeResponse({
    required super.mmrpc,
    required this.amount,
    this.amountFraction,
    this.amountRat,
  });

  /// Parses KDF's legacy answer, whose `result` is only a fraction.
  factory MaxTakerVolumeResponse.parse(JsonMap json) {
    final fraction = Fraction.fromJson(json.value<JsonMap>('result'));
    final ratio = Rational(
      BigInt.parse(fraction.numer),
      BigInt.parse(fraction.denom),
    );

    return MaxTakerVolumeResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      // Truncated, so the amount never exceeds what KDF allows.
      amount: ratio.toDecimal(scaleOnInfinitePrecision: 18).toString(),
      amountFraction: fraction,
      amountRat: ratio,
    );
  }

  /// Maximum tradable amount of `coin` as a string numeric, denominated in
  /// `coin` units, computed for the (`coin`, `trade_with`) pair.
  final String amount;

  /// Optional fractional representation of the amount
  final Fraction? amountFraction;

  /// Optional rational representation of the amount
  final Rational? amountRat;

  @override
  Map<String, dynamic> toJson() {
    final ratio = amountRat ?? Decimal.parse(amount).toRational();
    return {
      if (mmrpc != null) 'mmrpc': mmrpc,
      'result':
          amountFraction?.toJson() ??
          {
            'numer': ratio.numerator.toString(),
            'denom': ratio.denominator.toString(),
          },
    };
  }
}
