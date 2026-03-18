import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_defi_types/src/utils/protocol_type_utils.dart';

class Trc20Protocol extends ProtocolClass {
  Trc20Protocol._({
    required super.subClass,
    required super.config,
    super.isCustomToken = false,
  });

  factory Trc20Protocol.fromJson(JsonMap json, {CoinSubClass? subClass}) {
    _validateTrc20Config(json);
    return Trc20Protocol._(
      subClass: subClass ?? resolveProtocolSubClassFromConfig(json),
      isCustomToken: json.valueOrNull<bool>('is_custom_token') ?? false,
      config: json,
    );
  }

  static void _validateTrc20Config(JsonMap json) {
    final hasNodes = json.containsKey('nodes');
    final hasPlatform =
        json.valueOrNull<String>('protocol', 'protocol_data', 'platform') !=
        null;
    final hasContractAddress =
        json.valueOrNull<String>('contract_address') != null ||
        json.valueOrNull<String>(
              'protocol',
              'protocol_data',
              'contract_address',
            ) !=
            null;

    if (!hasNodes) {
      throw MissingProtocolFieldException('RPC nodes', 'nodes');
    }
    if (!hasPlatform) {
      throw MissingProtocolFieldException(
        'Platform coin',
        'protocol.protocol_data.platform',
      );
    }
    if (!hasContractAddress) {
      throw MissingProtocolFieldException(
        'Contract address',
        'protocol.protocol_data.contract_address',
      );
    }
  }

  List<EvmNode> get nodes =>
      config.value<JsonList>('nodes').map(EvmNode.fromJson).toList();

  String get platform =>
      config.value<String>('protocol', 'protocol_data', 'platform');

  @override
  bool get supportsMultipleAddresses => true;

  @override
  bool get requiresHdWallet => false;

  @override
  bool get isMemoSupported => false;

  @override
  Trc20ActivationParams defaultActivationParams({
    PrivateKeyPolicy privKeyPolicy = const PrivateKeyPolicy.contextPrivKey(),
  }) {
    return Trc20ActivationParams.fromJsonConfig(
      config,
    ).copyWith(privKeyPolicy: privKeyPolicy);
  }

  Trc20Protocol copyWith({
    List<EvmNode>? nodes,
    String? contractAddress,
    String? platform,
    bool? isCustomToken,
  }) {
    final protocol = JsonMap.of(
      config.valueOrNull<JsonMap>('protocol') ?? const <String, dynamic>{},
    );
    final protocolData = JsonMap.of(
      protocol.valueOrNull<JsonMap>('protocol_data') ??
          const <String, dynamic>{},
    );
    if (contractAddress != null) {
      protocolData['contract_address'] = contractAddress;
    }
    if (platform != null) {
      protocolData['platform'] = platform;
    }
    if (contractAddress != null || platform != null) {
      protocol['protocol_data'] = protocolData;
    }

    return Trc20Protocol._(
      subClass: subClass,
      isCustomToken: isCustomToken ?? this.isCustomToken,
      config: JsonMap.from(config)
        ..addAll({
          if (nodes != null)
            'nodes': nodes.map((node) => node.toJson()).toList(),
          if (contractAddress != null) 'contract_address': contractAddress,
          if (contractAddress != null || platform != null) 'protocol': protocol,
        }),
    );
  }
}
