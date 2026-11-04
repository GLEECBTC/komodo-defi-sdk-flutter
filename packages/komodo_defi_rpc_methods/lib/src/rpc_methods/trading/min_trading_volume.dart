import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:rational/rational.dart';

/// Request to get minimum trading volume for a coin
///
/// KDF serves `min_trading_vol` only on its legacy dispatcher, which it
/// reaches only when `mmrpc` is absent, and only for an activated coin.
class MinTradingVolumeRequest
    extends BaseRequest<MinTradingVolumeResponse, GeneralErrorResponse> {
  MinTradingVolumeRequest({required String rpcPass, required this.coin})
    : super(method: 'min_trading_vol', rpcPass: rpcPass, mmrpc: null);

  /// Coin ticker to query minimum trading volume for
  final String coin;

  @override
  Map<String, dynamic> toJson() => super.toJson().deepMerge({'coin': coin});

  @override
  MinTradingVolumeResponse parse(Map<String, dynamic> json) =>
      MinTradingVolumeResponse.parse(json);
}

/// Response with minimum trading volume
class MinTradingVolumeResponse extends BaseResponse {
  MinTradingVolumeResponse({
    required super.mmrpc,
    required this.amount,
    this.amountFraction,
    this.amountRat,
  });

  factory MinTradingVolumeResponse.parse(JsonMap json) {
    final result = json.value<JsonMap>('result');

    return MinTradingVolumeResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      amount: result.value<String>('min_trading_vol'),
      amountFraction:
          result.valueOrNull<JsonMap>('min_trading_vol_fraction') != null
          ? Fraction.fromJson(result.value<JsonMap>('min_trading_vol_fraction'))
          : null,
      amountRat:
          result.valueOrNull<List<dynamic>>('min_trading_vol_rat') != null
          ? rationalFromMm2(result.value<List<dynamic>>('min_trading_vol_rat'))
          : null,
    );
  }

  /// Minimum tradeable amount as a string numeric (coin units)
  final String amount;

  /// Optional fractional representation of the amount
  final Fraction? amountFraction;

  /// Optional rational representation of the amount
  final Rational? amountRat;

  @override
  Map<String, dynamic> toJson() => {
    if (mmrpc != null) 'mmrpc': mmrpc,
    'result': {
      'min_trading_vol': amount,
      if (amountFraction != null)
        'min_trading_vol_fraction': amountFraction!.toJson(),
      if (amountRat != null) 'min_trading_vol_rat': rationalToMm2(amountRat!),
    },
  };
}
