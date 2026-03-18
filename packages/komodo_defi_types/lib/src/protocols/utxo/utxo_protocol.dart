import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_defi_types/src/utils/protocol_type_utils.dart';

class UtxoProtocol extends ProtocolClass {
  UtxoProtocol._({
    required super.subClass,
    required super.config,
    super.supportedProtocols,
  });

  factory UtxoProtocol.fromJson(
    JsonMap json, {
    CoinSubClass? subClass,
    List<CoinSubClass> supportedProtocols = const [],
  }) {
    _validateUtxoConfig(json);
    return UtxoProtocol._(
      subClass: subClass ?? resolveProtocolSubClassFromConfig(json),
      config: json,
      supportedProtocols: supportedProtocols,
    );
  }

  @override
  // TODO: Consider the limitation this is likely to impose in the near
  // future when we need to confirgure activation parameters e.g. for Trezor.
  // A better solution may be to create a separate activation strategy rather
  // than adding the activation parameters to the protocol.
  // Hint: It may be useful to refactor `[ActivationStrategy.supportsAssetType]`
  // to be async.
  UtxoActivationParams defaultActivationParams({
    PrivateKeyPolicy privKeyPolicy = const PrivateKeyPolicy.contextPrivKey(),
  }) {
    var scanPolicy = ScanPolicy.scanIfNewWallet;
    if (privKeyPolicy == const PrivateKeyPolicy.trezor()) {
      scanPolicy = ScanPolicy.scan;
    }

    return UtxoActivationParams.fromJson(config)
        .copyWith(txHistory: true, privKeyPolicy: privKeyPolicy)
        .copyWithHd(
          minAddressesNumber: 1,
          scanPolicy: scanPolicy,
          gapLimit: 20,
        );
  }

  @override
  bool get supportsMultipleAddresses => true;

  @override
  bool get requiresHdWallet => false;

  @override
  bool get isMemoSupported => true;

  static void _validateUtxoConfig(JsonMap json) {
    if (json.value<bool>('is_testnet') == true) {
      return;
    }

    final requiredFields = <String, String>{
      // The validation below has been commented out as there are a few valid
      // coins that don't have these fields. Consider removing these checks or
      // adding the missing fields to the coins config.
      // 'pubtype': 'Public key type',
      // 'p2shtype': 'P2SH type',
      // 'wiftype': 'WIF type',
      // 'txfee': 'Transaction fee',
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
}
