import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_defi_types/src/utils/protocol_type_utils.dart';

class TrxProtocol extends ProtocolClass {
  TrxProtocol._({
    required super.subClass,
    required super.config,
    super.isCustomToken = false,
  });

  factory TrxProtocol.fromJson(JsonMap json, {CoinSubClass? subClass}) {
    _validateTrxConfig(json);
    return TrxProtocol._(
      subClass: subClass ?? resolveProtocolSubClassFromConfig(json),
      isCustomToken: json.valueOrNull<bool>('is_custom_token') ?? false,
      config: json,
    );
  }

  static void _validateTrxConfig(JsonMap json) {
    final hasNodes = json.containsKey('nodes');
    final hasProtocolType =
        json.valueOrNull<String>('protocol', 'type') != null;

    if (!hasNodes) {
      throw MissingProtocolFieldException('RPC nodes', 'nodes');
    }
    if (!hasProtocolType) {
      throw MissingProtocolFieldException('Protocol type', 'protocol.type');
    }
  }

  List<EvmNode> get nodes =>
      config.value<JsonList>('nodes').map(EvmNode.fromJson).toList();

  String? get network =>
      config.valueOrNull<String>('protocol', 'protocol_data', 'network');

  @override
  bool get supportsMultipleAddresses => true;

  @override
  bool get requiresHdWallet => false;

  @override
  bool get isMemoSupported => false;

  @override
  TrxWithTokensActivationParams defaultActivationParams({
    PrivateKeyPolicy privKeyPolicy = const PrivateKeyPolicy.contextPrivKey(),
  }) {
    return TrxWithTokensActivationParams.fromJson(
      config,
    ).copyWith(privKeyPolicy: privKeyPolicy);
  }

  TrxProtocol copyWith({
    List<EvmNode>? nodes,
    String? network,
    bool? isCustomToken,
  }) {
    final protocol = JsonMap.of(
      config.valueOrNull<JsonMap>('protocol') ?? const <String, dynamic>{},
    );
    final protocolData = JsonMap.of(
      protocol.valueOrNull<JsonMap>('protocol_data') ??
          const <String, dynamic>{},
    );
    if (network != null) {
      protocolData['network'] = network;
      protocol['protocol_data'] = protocolData;
    }

    return TrxProtocol._(
      subClass: subClass,
      isCustomToken: isCustomToken ?? this.isCustomToken,
      config: JsonMap.from(config)
        ..addAll({
          if (nodes != null)
            'nodes': nodes.map((node) => node.toJson()).toList(),
          if (network != null) 'protocol': protocol,
        }),
    );
  }
}
