import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request to get directly connected peers.
class GetDirectlyConnectedPeersRequest
    extends
        BaseRequest<GetDirectlyConnectedPeersResponse, GeneralErrorResponse> {
  GetDirectlyConnectedPeersRequest({required String rpcPass})
    : super(
        method: 'get_directly_connected_peers',
        rpcPass: rpcPass,
        mmrpc: null,
      );

  @override
  GetDirectlyConnectedPeersResponse parse(Map<String, dynamic> json) =>
      GetDirectlyConnectedPeersResponse.parse(json);
}

/// Response from `get_directly_connected_peers`.
class GetDirectlyConnectedPeersResponse extends BaseResponse {
  GetDirectlyConnectedPeersResponse({
    required super.mmrpc,
    required this.peers,
  });

  factory GetDirectlyConnectedPeersResponse.parse(JsonMap json) {
    final peersJson = json.valueOrNull<JsonMap>('result') ?? {};
    return GetDirectlyConnectedPeersResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      peers: peersJson.entries.map((entry) {
        final addresses = entry.value is List
            ? (entry.value as List).map((value) => value.toString()).toList()
            : <String>[];
        return DirectlyConnectedPeer(
          peerId: entry.key,
          peerAddresses: addresses,
        );
      }).toList(),
    );
  }

  /// Directly connected peers.
  final List<DirectlyConnectedPeer> peers;

  @override
  Map<String, dynamic> toJson() => {
    if (mmrpc != null) 'mmrpc': mmrpc,
    'result': {for (final peer in peers) peer.peerId: peer.peerAddresses},
  };
}

/// Peer id and currently connected addresses.
class DirectlyConnectedPeer {
  const DirectlyConnectedPeer({
    required this.peerId,
    required this.peerAddresses,
  });

  /// Peer id.
  final String peerId;

  /// Connected peer addresses.
  final List<String> peerAddresses;
}
