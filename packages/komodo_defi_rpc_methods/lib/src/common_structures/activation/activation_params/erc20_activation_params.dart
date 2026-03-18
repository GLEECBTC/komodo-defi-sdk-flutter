import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

class Erc20ActivationParams extends ActivationParams {
  Erc20ActivationParams({
    required this.nodes,
    required this.swapContractAddress,
    required this.fallbackSwapContract,
    super.privKeyPolicy,
  });

  factory Erc20ActivationParams.fromJsonConfig(JsonMap json) {
    return Erc20ActivationParams(
      nodes: json.value<JsonList>('nodes').map(EvmNode.fromJson).toList(),
      swapContractAddress: json['swap_contract_address'] as String,
      fallbackSwapContract: json['fallback_swap_contract'] as String,
    );
  }
  final List<EvmNode> nodes;
  final String swapContractAddress;
  final String fallbackSwapContract;

  Erc20ActivationParams copyWith({
    List<EvmNode>? nodes,
    String? swapContractAddress,
    String? fallbackSwapContract,
    PrivateKeyPolicy? privKeyPolicy,
  }) {
    return Erc20ActivationParams(
      nodes: nodes ?? this.nodes,
      swapContractAddress: swapContractAddress ?? this.swapContractAddress,
      fallbackSwapContract: fallbackSwapContract ?? this.fallbackSwapContract,
      privKeyPolicy: privKeyPolicy ?? this.privKeyPolicy,
    );
  }

  @override
  JsonMap toRpcParams() => super.toRpcParams().deepMerge({
    // Align with KDF API which expects node objects (url/gui_auth), not plain strings
    'nodes': nodes.map((e) => e.toJson()).toList(),
    'swap_contract_address': swapContractAddress,
    'fallback_swap_contract': fallbackSwapContract,
    // Ensure priv_key_policy uses the structured JSON object for EVM
    'priv_key_policy': privKeyPolicy?.toJson(),
  });
}
