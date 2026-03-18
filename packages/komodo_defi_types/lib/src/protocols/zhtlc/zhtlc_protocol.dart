import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_defi_types/src/utils/protocol_type_utils.dart';

class ZhtlcProtocol extends ProtocolClass {
  ZhtlcProtocol._({required super.subClass, required super.config});

  factory ZhtlcProtocol.fromJson(JsonMap json, {CoinSubClass? subClass}) {
    _validateZhtlcConfig(json);
    return ZhtlcProtocol._(
      subClass: subClass ?? resolveProtocolSubClassFromConfig(json),
      config: json,
    );
  }

  @override
  bool get supportsMultipleAddresses => false;

  @override
  bool get requiresHdWallet => false;

  @override
  bool get isMemoSupported => true;

  static void _validateZhtlcConfig(JsonMap json) {
    // ZHTLC can operate in Light mode using lightwalletd and optionally electrum servers.
    // We require at least one of electrum servers or light wallet d servers to be present.

    // Backward compatibility: some configs provided 'electrum' under config used by Electrum mode
    final hasElectrum =
        json.containsKey('electrum') || json.containsKey('electrum_servers');
    final hasLightWalletD = json.containsKey('light_wallet_d_servers');

    if (!hasElectrum && !hasLightWalletD) {
      throw MissingProtocolFieldException(
        'Electrum or LightwalletD servers',
        'electrum | light_wallet_d_servers',
      );
    }
  }

  String get zcashParamsPath =>
      config.valueOrNull<String>('zcash_params_path') ?? '';
}
