import 'package:komodo_defi_rpc_methods/src/common_structures/common_structures.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// SIA-specific activation parameters
///
/// Supports:
/// - serverUrl: SiaScan-compatible wallet API base URL
/// - txHistory: whether to fetch transaction history on enable
/// - requiredConfirmations: confirmations to wait for swap steps
class SiaActivationParams extends ActivationParams {
  const SiaActivationParams({
    required this.serverUrl,
    this.txHistory = true,
    int? requiredConfirmations,
    PrivateKeyPolicy privKeyPolicy = const PrivateKeyPolicy.contextPrivKey(),
  }) : super(
          requiredConfirmations: requiredConfirmations,
          privKeyPolicy: privKeyPolicy,
        );

  factory SiaActivationParams.fromConfigJson(JsonMap json) {
    String? serverUrl = json.valueOrNull<String>('server_url');
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

  final String serverUrl;
  final bool txHistory;

  @override
  Map<String, dynamic> toRpcParams() => super.toRpcParams().deepMerge({
        'client_conf': {
          'server_url': serverUrl,
        },
        'tx_history': txHistory,
      });
}

