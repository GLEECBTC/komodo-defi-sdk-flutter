import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_defi_types/src/utils/protocol_type_utils.dart';

class Erc20Protocol extends ProtocolClass {
  Erc20Protocol._({
    required super.subClass,
    required super.config,
    super.isCustomToken = false,
  });

  factory Erc20Protocol.fromJson(JsonMap json, {CoinSubClass? subClass}) {
    _validateErc20Config(json);
    return Erc20Protocol._(
      subClass: subClass ?? resolveProtocolSubClassFromConfig(json),
      isCustomToken: json.valueOrNull<bool>('is_custom_token') ?? false,
      config: json,
    );
  }

  @override
  bool get supportsMultipleAddresses => true;

  @override
  bool get requiresHdWallet => false;

  @override
  bool get isMemoSupported => false;

  @override
  ActivationParams defaultActivationParams({PrivateKeyPolicy? privKeyPolicy}) {
    // For ERC20, we typically don't need child tokens in the default case
    // If you need to support child tokens, you can add an overloaded method
    return Erc20ActivationParams.fromJsonConfig(
      super.config,
    ).copyWith(privKeyPolicy: privKeyPolicy);
  }

  ActivationParams activationParamsWithTokens([List<Asset>? childTokens]) {
    return childTokens == null
        ? Erc20ActivationParams.fromJsonConfig(super.config)
        : EthWithTokensActivationParams.fromJson(config).copyWith(
            erc20Tokens: childTokens
                .map((token) => TokensRequest(ticker: token.id.id))
                .toList(),
            txHistory: true,
          );
  }

  static void _validateErc20Config(JsonMap json) {
    final requiredFields = {
      'nodes': 'RPC nodes',
      'swap_contract_address': 'Swap contract',
      'fallback_swap_contract': 'Fallback swap contract',
    };

    for (final field in requiredFields.entries) {
      if (!json.containsKey(field.key)) {
        throw MissingProtocolFieldException(field.value, field.key);
      }
    }
  }

  List<EvmNode> get nodes =>
      config.value<JsonList>('nodes').map(EvmNode.fromJson).toList();

  String get swapContractAddress =>
      config.value<String>('swap_contract_address');

  String get fallbackSwapContract =>
      config.value<String>('fallback_swap_contract');

  @override
  // TODO: Confirm if this is correct, or if it is only for 'ERC20' and 'ETH'
  // protocols as is in the legacy repository.
  bool get needs0xPrefix => true;

  Erc20Protocol copyWith({
    int? chainId,
    List<EvmNode>? nodes,
    String? swapContractAddress,
    String? fallbackSwapContract,
    bool? isCustomToken,
  }) {
    return Erc20Protocol._(
      subClass: subClass,
      isCustomToken: isCustomToken ?? this.isCustomToken,
      config: JsonMap.from(config)
        ..addAll({
          if (chainId != null) 'chain_id': chainId,
          if (nodes != null)
            'nodes': nodes.map((node) => node.toJson()).toList(),
          if (swapContractAddress != null)
            'swap_contract_address': swapContractAddress,
          if (fallbackSwapContract != null)
            'fallback_swap_contract': fallbackSwapContract,
        }),
    );
  }
}
