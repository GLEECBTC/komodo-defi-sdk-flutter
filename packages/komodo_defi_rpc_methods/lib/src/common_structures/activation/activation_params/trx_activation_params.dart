import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

class TrxWithTokensActivationParams extends ActivationParams {
  TrxWithTokensActivationParams({
    required this.nodes,
    required this.tokenRequests,
    required this.txHistory,
    this.mm2,
    required super.privKeyPolicy,
    super.requiredConfirmations,
    super.requiresNotarization = false,
  });

  factory TrxWithTokensActivationParams.fromJson(JsonMap json) {
    final base = ActivationParams.fromConfigJson(json);

    return TrxWithTokensActivationParams(
      nodes: json.value<List<JsonMap>>('nodes').map(EvmNode.fromJson).toList(),
      tokenRequests:
          json
              .valueOrNull<List<JsonMap>>('erc20_tokens_requests')
              ?.map(TokensRequest.fromJson)
              .toList() ??
          [],
      requiredConfirmations: base.requiredConfirmations,
      requiresNotarization: base.requiresNotarization,
      privKeyPolicy: base.privKeyPolicy,
      txHistory: json.valueOrNull<bool>('tx_history'),
      mm2: json.valueOrNull<int>('mm2'),
    );
  }

  final List<EvmNode> nodes;
  final List<TokensRequest> tokenRequests;
  final bool? txHistory;
  final int? mm2;

  TrxWithTokensActivationParams copyWith({
    List<EvmNode>? nodes,
    List<TokensRequest>? tokenRequests,
    int? requiredConfirmations,
    bool? requiresNotarization,
    PrivateKeyPolicy? privKeyPolicy,
    bool? txHistory,
    int? mm2,
  }) {
    return TrxWithTokensActivationParams(
      nodes: nodes ?? this.nodes,
      tokenRequests: tokenRequests ?? this.tokenRequests,
      requiredConfirmations:
          requiredConfirmations ?? this.requiredConfirmations,
      requiresNotarization: requiresNotarization ?? this.requiresNotarization,
      privKeyPolicy: privKeyPolicy ?? this.privKeyPolicy,
      txHistory: txHistory ?? this.txHistory,
      mm2: mm2 ?? this.mm2,
    );
  }

  @override
  JsonMap toRpcParams() {
    return {
      ...super.toRpcParams(),
      'nodes': nodes.map((e) => e.toJson()).toList(),
      'erc20_tokens_requests': tokenRequests.map((e) => e.toJson()).toList(),
      if (txHistory != null) 'tx_history': txHistory,
      if (mm2 != null) 'mm2': mm2,
      'priv_key_policy':
          (privKeyPolicy ?? const PrivateKeyPolicy.contextPrivKey()).toJson(),
    };
  }
}
