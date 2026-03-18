import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

class Trc20ActivationParams extends ActivationParams {
  Trc20ActivationParams({required this.nodes, super.privKeyPolicy});

  factory Trc20ActivationParams.fromJsonConfig(JsonMap json) {
    return Trc20ActivationParams(
      nodes: json.value<JsonList>('nodes').map(EvmNode.fromJson).toList(),
    );
  }

  final List<EvmNode> nodes;

  Trc20ActivationParams copyWith({
    List<EvmNode>? nodes,
    PrivateKeyPolicy? privKeyPolicy,
  }) {
    return Trc20ActivationParams(
      nodes: nodes ?? this.nodes,
      privKeyPolicy: privKeyPolicy ?? this.privKeyPolicy,
    );
  }

  @override
  JsonMap toRpcParams() => super.toRpcParams().deepMerge({
    'nodes': nodes.map((e) => e.toJson()).toList(),
    'priv_key_policy': privKeyPolicy?.toJson(),
  });
}
