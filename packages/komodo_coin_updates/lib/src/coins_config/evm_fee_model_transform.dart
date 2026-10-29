import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

import 'config_transform.dart';

/// Supplies KDF fee models absent from older bundled or cached coin configs.
/// Explicit settings remain authoritative; ERC-20s inherit the platform in KDF.
class EvmFeeModelTransform implements CoinConfigTransform {
  const EvmFeeModelTransform();

  static const _models = {
    8453: 'op_stack',
    5000: 'mantle',
    143: 'monad',
    43114: 'avalanche',
  };

  int? _chain(JsonMap config) =>
      config.valueOrNull<int>('protocol', 'protocol_data', 'chain_id');

  @override
  bool needsTransform(JsonMap config) =>
      !config.containsKey('fee_model') &&
      config.valueOrNull<String>('protocol', 'type') == 'ETH' &&
      _models.containsKey(_chain(config));

  @override
  JsonMap transform(JsonMap config) => needsTransform(config)
      ? {...config, 'fee_model': _models[_chain(config)]}
      : JsonMap.of(config);
}
