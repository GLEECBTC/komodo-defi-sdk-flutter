import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';

/// RPC namespace for KDF diagnostics.
class DiagnosticsMethodsNamespace extends BaseRpcMethodNamespace {
  DiagnosticsMethodsNamespace(super.client);

  /// Gets this node's peer id.
  Future<GetMyPeerIdResponse> getMyPeerId({String? rpcPass}) {
    return execute(GetMyPeerIdRequest(rpcPass: rpcPass ?? this.rpcPass ?? ''));
  }

  /// Gets directly connected peers.
  Future<GetDirectlyConnectedPeersResponse> getDirectlyConnectedPeers({
    String? rpcPass,
  }) {
    return execute(
      GetDirectlyConnectedPeersRequest(rpcPass: rpcPass ?? this.rpcPass ?? ''),
    );
  }

  /// Gets the running KDF version.
  Future<KdfVersionResponse> version({String? rpcPass}) {
    return execute(KdfVersionRequest(rpcPass: rpcPass ?? this.rpcPass ?? ''));
  }
}
