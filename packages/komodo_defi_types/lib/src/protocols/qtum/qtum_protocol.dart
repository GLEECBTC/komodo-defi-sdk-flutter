import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_defi_types/src/utils/protocol_type_utils.dart';

class QtumProtocol extends ProtocolClass {
  QtumProtocol._({required super.subClass, required super.config});

  factory QtumProtocol.fromJson(JsonMap json, {CoinSubClass? subClass}) {
    _validateQtumConfig(json);
    return QtumProtocol._(
      subClass: subClass ?? resolveProtocolSubClassFromConfig(json),
      config: json,
    );
  }

  @override
  bool get supportsMultipleAddresses => true;

  @override
  bool get requiresHdWallet => false;

  @override
  bool get isMemoSupported => false;

  static void _validateQtumConfig(JsonMap json) {
    final requiredFields = {
      'pubtype': 'Public key type',
      'p2shtype': 'P2SH type',
      'wiftype': 'WIF type',
      'txfee': 'Transaction fee',
      'electrum': 'Electrum servers',
    };

    for (final field in requiredFields.entries) {
      if (!json.containsKey(field.key)) {
        throw MissingProtocolFieldException(field.value, field.key);
      }
    }
  }

  int? get pubtype => config.valueOrNull<int>('pubtype');
  int? get p2shtype => config.valueOrNull<int>('p2shtype');
  int? get wiftype => config.valueOrNull<int>('wiftype');
  int? get txVersion => config.valueOrNull<int>('txversion');
  int? get txFee => config.valueOrNull<int>('txfee');
  bool get overwintered => config.valueOrNull<bool>('overwintered') ?? false;

  // TODO!
  @override
  QtumActivationParams defaultActivationParams({
    int? minAddressesNumber,
    ScanPolicy? scanPolicy,
    int? gapLimit,
    // TODO! Cater for Trezor
    PrivateKeyPolicy privKeyPolicy = const PrivateKeyPolicy.contextPrivKey(),
    List<ActivationServers>? electrum,
  }) {
    return QtumActivationParams.fromConfigJson(config).genericCopyWith(
      minAddressesNumber: minAddressesNumber,
      scanPolicy: scanPolicy,
      gapLimit: gapLimit,
      privKeyPolicy: privKeyPolicy,
    );
  }
}
