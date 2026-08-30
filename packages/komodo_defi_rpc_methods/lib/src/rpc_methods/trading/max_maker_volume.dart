import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request to get the maximum maker volume for a coin.
class MaxMakerVolumeRequest
    extends BaseRequest<MaxMakerVolumeResponse, GeneralErrorResponse> {
  MaxMakerVolumeRequest({required String rpcPass, required this.coin})
    : super(method: 'max_maker_vol', rpcPass: rpcPass, mmrpc: RpcVersion.v2_0);

  /// Coin ticker to compute max maker volume for.
  final String coin;

  @override
  Map<String, dynamic> toJson() => super.toJson().deepMerge({
    'params': {'coin': coin},
  });

  @override
  MaxMakerVolumeResponse parse(Map<String, dynamic> json) =>
      MaxMakerVolumeResponse.parse(json);
}

/// Response with max maker volume and current balance for the requested coin.
class MaxMakerVolumeResponse extends BaseResponse {
  MaxMakerVolumeResponse({
    required super.mmrpc,
    required this.coin,
    required this.volume,
    required this.balance,
  });

  factory MaxMakerVolumeResponse.parse(JsonMap json) {
    final result = json.value<JsonMap>('result');

    return MaxMakerVolumeResponse(
      mmrpc: json.value<String>('mmrpc'),
      coin: result.value<String>('coin'),
      volume: NumericValue.fromJson(result.value<JsonMap>('volume')),
      balance: NumericValue.fromJson(result.value<JsonMap>('balance')),
    );
  }

  /// Coin ticker used for the request.
  final String coin;

  /// Maximum maker volume available for placing a maker order.
  final NumericValue volume;

  /// Current available balance reported alongside the maker volume.
  final NumericValue balance;

  @override
  Map<String, dynamic> toJson() => {
    'mmrpc': mmrpc,
    'result': {
      'coin': coin,
      'volume': volume.toJson(),
      'balance': balance.toJson(),
    },
  };
}
