import 'package:komodo_defi_rpc_methods/src/common_structures/common_structures.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Activation parameters specific to SIA protocol coins.
///
/// This extends the generic [ActivationParams] with:
/// - a required [serverUrl] pointing at a SiaScan-compatible wallet API
/// - an optional [password] for the SIA wallet daemon
/// - a [txHistory] flag that controls whether transaction history is enabled
///
/// The shape produced by [toRpcParams] matches the KDF
/// `task::enable_sia::init` API, nesting values under `activation_params.client_conf`.
class SiaActivationParams extends ActivationParams {
  const SiaActivationParams({
    required this.serverUrl,
    this.password,
    this.txHistory = true,
    super.requiredConfirmations,
    super.privKeyPolicy,
  });

  /// Creates [SiaActivationParams] from a coins-config JSON entry.
  ///
  /// The SIA server URL is taken from:
  /// - `server_url`, or
  /// - the first `nodes[].url` entry as a fallback.
  ///
  /// Throws [ArgumentError] if no usable URL can be found.
  factory SiaActivationParams.fromConfigJson(JsonMap json) {
    var serverUrl = json.valueOrNull<String>('server_url');
    if (serverUrl == null && json.containsKey('nodes')) {
      final nodes = json.value<List<dynamic>>('nodes');
      if (nodes.isNotEmpty) {
        final first = nodes.first;
        if (first is Map<String, dynamic> && first.containsKey('url')) {
          serverUrl = first['url'] as String?;
        }
      }
    }
    if (serverUrl == null) {
      throw ArgumentError(
        'SIA activation requires server_url (or nodes[].url) sourced from coins config',
      );
    }
    return SiaActivationParams(
      serverUrl: serverUrl,
      txHistory: json.valueOrNull<bool>('tx_history') ?? true,
      requiredConfirmations: json.valueOrNull<int>('required_confirmations'),
      privKeyPolicy: PrivateKeyPolicy.fromLegacyJson(
        json.valueOrNull<dynamic>('priv_key_policy'),
      ),
    );
  }

  /// Base URL of the SIA wallet API (e.g. `https://api.siascan.com/wallet/api`).
  final String serverUrl;

  /// Optional password to unlock or authenticate the SIA wallet daemon.
  final String? password;

  /// Whether SIA transaction history should be enabled on activation.
  final bool txHistory;

  @override
  Map<String, dynamic> toRpcParams() => super.toRpcParams().deepMerge({
    // SIA activation uses a nested client_conf object
    'client_conf': {'server_url': serverUrl, 'password': ?password},
    'tx_history': txHistory,
  });
}
