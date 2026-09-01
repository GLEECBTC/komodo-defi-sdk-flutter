import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

class GetPublicKeyHashRequest
    extends BaseRequest<GetPublicKeyHashResponse, GeneralErrorResponse> {
  GetPublicKeyHashRequest({required super.rpcPass})
    : super(method: 'get_public_key_hash', mmrpc: RpcVersion.v2_0);

  // `<JsonMap>{}` is an empty **Set**, not an empty Map: a single type
  // argument on `{}` makes it a set literal. `jsonEncode` rejects it with
  // "Converting object to an encodable object failed: _Set len:0", so this
  // request could never be sent over any transport that serialises to JSON -
  // which is every non-web one (`KdfOperationsRemote.mm2Rpc`,
  // `KdfOperationsNativeLibrary.mm2Rpc`). It stayed dormant from 2024 because
  // nothing exercised this method through an encoding transport.
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'params': <String, dynamic>{},
  };

  @override
  GetPublicKeyHashResponse parse(Map<String, dynamic> json) =>
      GetPublicKeyHashResponse.parse(json);
}

class GetPublicKeyHashResponse extends BaseResponse {
  GetPublicKeyHashResponse({required super.mmrpc, required this.publicKeyHash});

  factory GetPublicKeyHashResponse.parse(Map<String, dynamic> json) {
    return GetPublicKeyHashResponse(
      mmrpc: json.value<String>('mmrpc'),
      publicKeyHash: json.value<String>('result', 'public_key_hash'),
    );
  }

  final String publicKeyHash;

  @override
  Map<String, dynamic> toJson() => {
    'mmrpc': mmrpc,
    'result': {'public_key_hash': publicKeyHash},
  };
}
