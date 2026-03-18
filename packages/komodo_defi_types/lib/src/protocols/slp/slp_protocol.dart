import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_defi_types/src/utils/protocol_type_utils.dart';

class SlpProtocol extends ProtocolClass {
  SlpProtocol._({
    required super.subClass,
    required super.config,
    required super.supportedProtocols,
  });

  factory SlpProtocol.fromJson(
    JsonMap json, {
    CoinSubClass? subClass,
    List<CoinSubClass> supportedProtocols = const [],
  }) {
    _validateSlpConfig(json);
    return SlpProtocol._(
      subClass: subClass ?? resolveProtocolSubClassFromConfig(json),
      config: json,
      supportedProtocols: supportedProtocols,
    );
  }

  @override
  bool get supportsMultipleAddresses => true;

  @override
  bool get requiresHdWallet => false;

  @override
  bool get isMemoSupported => false;

  static void _validateSlpConfig(JsonMap json) {
    // Only required for parent assets
    if (json.valueOrNull<String>('parent_coin') != null) {
      return;
    }

    final requiredFields = {
      'bchd_urls': 'BCHD URLs',
      'electrum': 'Electrum servers',
    };

    for (final field in requiredFields.entries) {
      if (!json.containsKey(field.key)) {
        throw MissingProtocolFieldException(field.value, field.key);
      }
    }
  }

  List<String> get bchdUrls =>
      config.value<List<dynamic>>('bchd_urls').cast<String>();
}
