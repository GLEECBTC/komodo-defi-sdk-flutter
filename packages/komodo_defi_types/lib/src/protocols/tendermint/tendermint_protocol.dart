import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_defi_types/src/utils/protocol_type_utils.dart';

class TendermintProtocol extends ProtocolClass {
  TendermintProtocol._({
    required super.subClass,
    required super.config,
    super.supportedProtocols,
  });

  factory TendermintProtocol.fromJson(
    JsonMap json, {
    CoinSubClass? subClass,
    List<CoinSubClass> supportedProtocols = const [],
  }) {
    _validateTendermintConfig(json);
    return TendermintProtocol._(
      subClass: subClass ?? resolveProtocolSubClassFromConfig(json),
      config: json,
      supportedProtocols: supportedProtocols,
    );
  }

  static void _validateTendermintConfig(JsonMap json) {
    final requiredFields = {
      'rpc_urls': 'RPC URLs',
      // 'account_prefix': 'Account prefix',
      // 'chain_id': 'Chain ID',
    };

    for (final field in requiredFields.entries) {
      if (!json.containsKey(field.key)) {
        throw MissingProtocolFieldException(field.value, field.key);
      }
    }
  }

  JsonList get rpcUrlsMap => config.value<JsonList>('rpc_urls');

  String? get accountPrefix => config.valueOrNull<String>('account_prefix');

  String? get chainId =>
      config.valueOrNull<String>('protocol', 'protocol_data', 'chain_id');

  @override
  bool get supportsMultipleAddresses => false;

  @override
  bool get requiresHdWallet => false;

  @override
  bool get isMemoSupported => false;

  /// Create default activation params for Tendermint protocol.
  /// Tendermint is single-address only, so no HD wallet parameters are used.
  @override
  TendermintActivationParams defaultActivationParams({
    PrivateKeyPolicy privKeyPolicy = const PrivateKeyPolicy.contextPrivKey(),
  }) {
    // Create a config with mode if not present
    final configWithMode = JsonMap.of(config)
      ..setIfAbsentOrEmpty(
        'mode',
        () => {
          'rpc': ActivationModeType.electrum.value,
          'rpc_data': {'electrum': rpcUrlsMap},
        },
      );

    // Get base parameters from config and set single-address defaults
    return TendermintActivationParams.fromJson(configWithMode).copyWith(
      txHistory: true,
      privKeyPolicy: privKeyPolicy,
      getBalances: true,
    );
  }
}
