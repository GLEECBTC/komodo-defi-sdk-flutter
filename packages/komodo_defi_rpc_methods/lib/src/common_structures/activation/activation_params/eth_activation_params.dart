import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

class EthWithTokensActivationParams extends ActivationParams {
  EthWithTokensActivationParams({
    required this.nodes,
    required this.swapContractAddress,
    required this.fallbackSwapContract,
    required this.erc20Tokens,
    required this.txHistory,
    required super.privKeyPolicy,
    this.gapLimit,
    super.requiredConfirmations,
    super.requiresNotarization = false,
  });

  factory EthWithTokensActivationParams.fromJson(JsonMap json) {
    final base = ActivationParams.fromConfigJson(json);

    return EthWithTokensActivationParams(
      nodes: json.value<List<JsonMap>>('nodes').map(EvmNode.fromJson).toList(),
      swapContractAddress: json.value<String>('swap_contract_address'),
      fallbackSwapContract: json.value<String>('fallback_swap_contract'),
      erc20Tokens:
          json
              .valueOrNull<List<JsonMap>>('erc20_tokens_requests')
              ?.map(TokensRequest.fromJson)
              .toList() ??
          [],
      requiredConfirmations: base.requiredConfirmations,
      requiresNotarization: base.requiresNotarization,
      privKeyPolicy: base.privKeyPolicy,
      txHistory: json.valueOrNull<bool>('tx_history'),
      gapLimit: json.valueOrNull<int>('gap_limit'),
    );
  }

  final List<EvmNode> nodes;
  final String swapContractAddress;
  final String fallbackSwapContract;
  final List<TokensRequest> erc20Tokens;

  final bool? txHistory;

  /// How far KDF walks past the last used address during activation.
  ///
  /// KDF reads this off `EthActivationV2Request.gap_limit`
  /// (`mm2src/coins/eth/v2_activation.rs:232-260`) and falls back to
  /// `DEFAULT_GAP_LIMIT` = 20 when absent - which is what the SDK used to let
  /// it do. Sent explicitly now so the ETH-family walk follows the same policy
  /// as every other HD chain. See `HdGapLimit`.
  ///
  /// Only meaningful on the platform coin: tokens `Arc::clone` the platform's
  /// pool and HD account rather than walking their own gap.
  final int? gapLimit;

  EthWithTokensActivationParams copyWith({
    List<EvmNode>? nodes,
    String? swapContractAddress,
    String? fallbackSwapContract,
    List<TokensRequest>? erc20Tokens,
    int? requiredConfirmations,
    bool? requiresNotarization,
    PrivateKeyPolicy? privKeyPolicy,
    bool? txHistory,
    int? gapLimit,
  }) {
    return EthWithTokensActivationParams(
      nodes: nodes ?? this.nodes,
      swapContractAddress: swapContractAddress ?? this.swapContractAddress,
      fallbackSwapContract: fallbackSwapContract ?? this.fallbackSwapContract,
      erc20Tokens: erc20Tokens ?? this.erc20Tokens,
      requiredConfirmations:
          requiredConfirmations ?? this.requiredConfirmations,
      requiresNotarization: requiresNotarization ?? this.requiresNotarization,
      privKeyPolicy: privKeyPolicy ?? this.privKeyPolicy,
      txHistory: txHistory ?? this.txHistory,
      gapLimit: gapLimit ?? this.gapLimit,
    );
  }

  @override
  Map<String, dynamic> toRpcParams() {
    return {
      ...super.toRpcParams(),
      // Expands each config node into its https entry plus, where the config
      // publishes a usable one, a second entry for its ws_url. See
      // [EvmNode.toRpcNodeList] - additive, never a replacement.
      'nodes': EvmNode.toRpcNodeList(nodes),
      'swap_contract_address': swapContractAddress,
      'fallback_swap_contract': fallbackSwapContract,
      'erc20_tokens_requests': erc20Tokens.map((e) => e.toJson()).toList(),
      if (txHistory != null) 'tx_history': txHistory,
      if (gapLimit != null) 'gap_limit': gapLimit,
      // Override priv_key_policy with object form for ETH/ERC20
      'priv_key_policy':
          (privKeyPolicy ?? const PrivateKeyPolicy.contextPrivKey()).toJson(),
    };
  }
}
