import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

class Trc20ActivationParams extends ActivationParams {
  Trc20ActivationParams({
    required this.nodes,
    super.privKeyPolicy,
    this.gasless,
  });

  factory Trc20ActivationParams.fromJsonConfig(JsonMap json) {
    final gasless = json.valueOrNull<JsonMap>('gasless');
    return Trc20ActivationParams(
      nodes: json.value<JsonList>('nodes').map(EvmNode.fromJson).toList(),
      gasless: gasless == null
          ? null
          : TronGaslessTokenActivationConfig.fromJson(gasless),
    );
  }

  final List<EvmNode> nodes;
  final TronGaslessTokenActivationConfig? gasless;

  Trc20ActivationParams copyWith({
    List<EvmNode>? nodes,
    PrivateKeyPolicy? privKeyPolicy,
    TronGaslessTokenActivationConfig? gasless,
  }) {
    return Trc20ActivationParams(
      nodes: nodes ?? this.nodes,
      privKeyPolicy: privKeyPolicy ?? this.privKeyPolicy,
      gasless: gasless ?? this.gasless,
    );
  }

  @override
  JsonMap toRpcParams() => super.toRpcParams().deepMerge({
    'nodes': nodes.map((e) => e.toJson()).toList(),
    'priv_key_policy': privKeyPolicy?.toJson(),
    if (gasless != null) 'gasless': gasless!.toJson(),
  });
}
