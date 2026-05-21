import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request to get this node's peer id.
class GetMyPeerIdRequest
    extends BaseRequest<GetMyPeerIdResponse, GeneralErrorResponse> {
  GetMyPeerIdRequest({required String rpcPass})
    : super(method: 'get_my_peer_id', rpcPass: rpcPass, mmrpc: null);

  @override
  GetMyPeerIdResponse parse(Map<String, dynamic> json) =>
      GetMyPeerIdResponse.parse(json);
}

/// Response from `get_my_peer_id`.
class GetMyPeerIdResponse extends BaseResponse {
  GetMyPeerIdResponse({required super.mmrpc, required this.peerId});

  factory GetMyPeerIdResponse.parse(JsonMap json) {
    return GetMyPeerIdResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      peerId: json.value<String>('result'),
    );
  }

  /// Local node peer id.
  final String peerId;

  @override
  Map<String, dynamic> toJson() => {
    if (mmrpc != null) 'mmrpc': mmrpc,
    'result': peerId,
  };
}
