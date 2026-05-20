import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// High-level diagnostics and lifecycle helpers over KDF RPCs.
class DiagnosticsManager {
  /// Creates a [DiagnosticsManager].
  DiagnosticsManager(this._client);

  final ApiClient _client;

  /// Disables an activated coin and invalidates any caller-managed cache.
  Future<DisableCoinResponse> disableCoin(String coin) {
    return _client.rpc.generalActivation.disableCoin(coin: coin);
  }

  /// Gets this node's peer id.
  Future<String> getMyPeerId() async {
    final response = await _client.rpc.diagnostics.getMyPeerId();
    return response.peerId;
  }

  /// Gets directly connected peers.
  Future<List<DirectlyConnectedPeer>> getDirectlyConnectedPeers() async {
    final response = await _client.rpc.diagnostics.getDirectlyConnectedPeers();
    return response.peers;
  }

  /// Gets the running KDF version string.
  Future<String> version() async {
    final response = await _client.rpc.diagnostics.version();
    return response.version;
  }
}
