import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/assets/activated_assets_cache.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// High-level diagnostics and lifecycle helpers over KDF RPCs.
class DiagnosticsManager {
  /// Creates a [DiagnosticsManager].
  DiagnosticsManager(this._client, {ActivatedAssetsCache? activatedAssetsCache})
    : _activatedAssetsCache = activatedAssetsCache;

  final ApiClient _client;
  final ActivatedAssetsCache? _activatedAssetsCache;

  /// Disables an activated coin and invalidates the activated-assets cache.
  Future<DisableCoinResponse> disableCoin(String coin) async {
    final response = await _client.rpc.generalActivation.disableCoin(
      coin: coin,
    );
    _activatedAssetsCache?.invalidate();
    return response;
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
