import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Exports the active coin's key through the authenticated legacy endpoint.
/// Callers must apply their wallet-unlock and secret-presentation policy.
class ShowPrivKeyRequest
    extends BaseRequest<ShowPrivKeyResponse, GeneralErrorResponse> {
  ShowPrivKeyRequest({required this.coin, super.rpcPass})
    : super(method: 'show_priv_key', mmrpc: RpcVersion.legacy);

  final String coin;

  @override
  JsonMap toJson() => {...super.toJson(), 'coin': coin};

  @override
  ShowPrivKeyResponse parse(JsonMap json) => ShowPrivKeyResponse.parse(json);
}

class ShowPrivKeyResponse extends BaseResponse {
  ShowPrivKeyResponse({required this.coin, required this.privKey})
    : super(mmrpc: RpcVersion.legacy);

  factory ShowPrivKeyResponse.parse(JsonMap json) => ShowPrivKeyResponse(
    coin: json.value<String>('result', 'coin'),
    privKey: json.value<String>('result', 'priv_key'),
  );

  final String coin;
  final String privKey;

  @override
  JsonMap toJson() => {
    'result': {'coin': coin, 'priv_key': privKey},
  };

  @override
  String toString() => 'ShowPrivKeyResponse(redacted)';
}
