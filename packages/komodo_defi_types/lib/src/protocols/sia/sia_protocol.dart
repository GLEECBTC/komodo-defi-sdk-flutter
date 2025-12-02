import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

class SiaProtocol extends ProtocolClass {
  SiaProtocol._({
    required super.subClass,
    required super.config,
    super.supportedProtocols,
  });

  factory SiaProtocol.fromJson(
    JsonMap json, {
    List<CoinSubClass> supportedProtocols = const [],
  }) {
    _validateSiaConfig(json);
    return SiaProtocol._(
      subClass: CoinSubClass.parse(json.value('type')),
      config: json,
      supportedProtocols: supportedProtocols,
    );
  }

  static void _validateSiaConfig(JsonMap json) {
    // Minimal required fields for SIA protocol configuration
    final requiredFields = {
      'nodes': 'Seed nodes list',
    };
    for (final field in requiredFields.entries) {
      if (!json.containsKey(field.key)) {
        throw MissingProtocolFieldException(field.value, field.key);
      }
    }
  }

  /// Optional SiaScan-compatible server URL used by SDK activation defaults.
  /// Resolves from `server_url` or falls back to first `nodes[i].url`.
  String? get serverUrl {
    final direct = config.valueOrNull<String>('server_url');
    if (direct != null) return direct;
    if (config.containsKey('nodes')) {
      final nodes = config.value<List<dynamic>>('nodes');
      if (nodes.isNotEmpty) {
        final first = nodes.first;
        if (first is Map<String, dynamic> && first.containsKey('url')) {
          return first['url'] as String?;
        }
      }
    }
    return null;
  }

  /// Number of confirmations required for steps like swaps
  int? get requiredConfirmations =>
      config.valueOrNull<int>('required_confirmations');

  /// SIA protocol does not support multiple addresses per account in KDF
  @override
  bool get supportsMultipleAddresses => false;

  @override
  bool get requiresHdWallet => false;

  @override
  bool get isMemoSupported => false;

  @override
  Uri? explorerTxUrl(String txHash) => null;

  @override
  Uri? explorerAddressUrl(String address) {
    // Use configured address pattern if present, otherwise fall back to SiaScan events URL
    final pattern =
        explorerPattern.addressPattern ?? 'addresses/{ADDRESS}/events/';
    return explorerPattern.buildUrl(pattern, {'ADDRESS': address});
  }
}
