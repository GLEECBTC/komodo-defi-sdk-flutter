import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';

/// Disables one runtime asset without changing the wallet's saved selection.
class DisableCoinRequest
    extends BaseRequest<DisableCoinResponse, GeneralErrorResponse> {
  DisableCoinRequest({required this.coin})
    : super(method: 'disable_coin', mmrpc: RpcVersion.legacy);

  final String coin;

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'coin': coin};

  @override
  DisableCoinResponse parse(Map<String, dynamic> json) {
    if (json['result'] != 'success') {
      throw const FormatException('Unexpected disable_coin result');
    }
    return DisableCoinResponse();
  }
}

class DisableCoinResponse extends BaseResponse {
  DisableCoinResponse() : super(mmrpc: RpcVersion.legacy);

  @override
  Map<String, dynamic> toJson() => {'result': 'success'};
}
