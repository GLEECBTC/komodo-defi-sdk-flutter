import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request to disable an activated coin.
class DisableCoinRequest
    extends BaseRequest<DisableCoinResponse, GeneralErrorResponse> {
  DisableCoinRequest({required String rpcPass, required this.coin})
    : super(method: 'disable_coin', rpcPass: rpcPass, mmrpc: null);

  /// Coin ticker/config id to disable.
  final String coin;

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'coin': coin};

  @override
  DisableCoinResponse parse(Map<String, dynamic> json) =>
      DisableCoinResponse.parse(json);
}

/// Response from `disable_coin`.
class DisableCoinResponse extends BaseResponse {
  DisableCoinResponse({required super.mmrpc, this.result});

  factory DisableCoinResponse.parse(JsonMap json) {
    return DisableCoinResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      result: json.valueOrNull<dynamic>('result'),
    );
  }

  /// Raw result payload, if KDF returned one.
  final dynamic result;

  @override
  Map<String, dynamic> toJson() => {
    if (mmrpc != null) 'mmrpc': mmrpc,
    if (result != null) 'result': result,
  };
}
