import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Enum representing the key export mode for private key retrieval
enum KeyExportMode {
  /// HD wallet mode - exports keys with derivation paths
  hd('hd'),

  /// Iguana mode - exports keys derived using the legacy iguana derivation path
  iguana('iguana');

  /// Constructor for KeyExportMode
  const KeyExportMode(this.value);

  factory KeyExportMode.fromString(String value) {
    switch (value.toLowerCase()) {
      case 'hd':
        return KeyExportMode.hd;
      case 'iguana':
        return KeyExportMode.iguana;
      default:
        throw ArgumentError('Unknown KeyExportMode: $value');
    }
  }

  final String value;

  @override
  String toString() => value;
}

/// Information about a coin's private key and address
class CoinKeyInfo {
  const CoinKeyInfo({
    required this.coin,
    required this.publicKeySecp256k1,
    required this.publicKeyAddress,
    required this.privKey,
  });

  factory CoinKeyInfo.fromJson(JsonMap json) {
    return CoinKeyInfo(
      coin: json.value<String>('coin'),
      publicKeySecp256k1: json.value<String>('pubkey'),
      publicKeyAddress: json.value<String>('address'),
      privKey: json.value<String>('priv_key'),
    );
  }

  final String coin;
  final String publicKeySecp256k1;
  final String publicKeyAddress;
  final String privKey;

  JsonMap toJson() {
    return {
      'coin': coin,
      'pubkey': publicKeySecp256k1,
      'address': publicKeyAddress,
      'priv_key': privKey,
    };
  }
}

/// Information about an HD address with derivation path
class HdAddressInfo {
  const HdAddressInfo({
    required this.derivationPath,
    required this.publicKeySecp256k1,
    required this.publicKeyAddress,
    required this.privKey,
  });

  factory HdAddressInfo.fromJson(JsonMap json) {
    return HdAddressInfo(
      derivationPath: json.value<String>('derivation_path'),
      publicKeySecp256k1: json.value<String>('pubkey'),
      publicKeyAddress: json.value<String>('address'),
      privKey: json.value<String>('priv_key'),
    );
  }

  final String derivationPath;
  final String publicKeySecp256k1;
  final String publicKeyAddress;
  final String privKey;

  JsonMap toJson() {
    return {
      'derivation_path': derivationPath,
      'pubkey': publicKeySecp256k1,
      'address': publicKeyAddress,
      'priv_key': privKey,
    };
  }
}

/// Information about a coin's HD wallet addresses
class HdCoinKeyInfo {
  const HdCoinKeyInfo({required this.coin, required this.addresses});

  factory HdCoinKeyInfo.fromJson(JsonMap json) {
    final addressesJson = json.value<JsonList>('addresses');
    final addresses = addressesJson.map(HdAddressInfo.fromJson).toList();

    return HdCoinKeyInfo(
      coin: json.value<String>('coin'),
      addresses: addresses,
    );
  }

  final String coin;
  final List<HdAddressInfo> addresses;

  JsonMap toJson() {
    return {
      'coin': coin,
      'addresses': addresses.map((addr) => addr.toJson()).toList(),
    };
  }
}

/// Request class for getting private keys
class GetPrivateKeysRequest
    extends BaseRequest<GetPrivateKeysResponse, GeneralErrorResponse> {
  GetPrivateKeysRequest({
    required super.rpcPass,
    required this.coins,
    this.mode,
    this.startIndex,
    this.endIndex,
    this.accountIndex,
  }) : super(method: 'get_private_keys', mmrpc: RpcVersion.v2_0);

  final List<String> coins;
  final KeyExportMode? mode;
  final int? startIndex;
  final int? endIndex;
  final int? accountIndex;

  @override
  JsonMap toJson() {
    return super.toJson().deepMerge({
      'params': {
        'coins': coins,
        if (mode != null) 'mode': mode!.value,
        if (startIndex != null) 'start_index': startIndex,
        if (endIndex != null) 'end_index': endIndex,
        if (accountIndex != null) 'account_index': accountIndex,
      },
    });
  }

  @override
  GetPrivateKeysResponse parse(JsonMap json) =>
      GetPrivateKeysResponse.parse(json);
}

/// Response class for getting private keys
///
/// This is an untagged union that can contain either standard keys or HD keys
/// based on the export mode used in the request.
class GetPrivateKeysResponse extends BaseResponse {
  GetPrivateKeysResponse._({
    required super.mmrpc,
    this.standardKeys,
    this.hdKeys,
  }) : assert(
         (standardKeys != null) ^ (hdKeys != null),
         'Exactly one of standardKeys or hdKeys must be non-null',
       );

  /// Constructor for standard keys response
  GetPrivateKeysResponse.standard({
    required String? mmrpc,
    required List<CoinKeyInfo> keys,
  }) : this._(mmrpc: mmrpc, standardKeys: keys);

  /// Constructor for HD keys response
  GetPrivateKeysResponse.hd({
    required String? mmrpc,
    required List<HdCoinKeyInfo> keys,
  }) : this._(mmrpc: mmrpc, hdKeys: keys);

  factory GetPrivateKeysResponse.parse(JsonMap json) {
    final mmrpc = json.valueOrNull<String>('mmrpc');
    final result = json.value<List<JsonMap>>('result');

    if (result.isEmpty) {
      // Default to standard response for empty result
      return GetPrivateKeysResponse.standard(mmrpc: mmrpc, keys: []);
    }

    if (result.first.containsKey('addresses')) {
      // This is an HD response - items have 'addresses' field
      final hdKeys = result.map(HdCoinKeyInfo.fromJson).toList();
      return GetPrivateKeysResponse.hd(mmrpc: mmrpc, keys: hdKeys);
    } else {
      // This is a standard response - items have direct key fields
      final standardKeys = result.map(CoinKeyInfo.fromJson).toList();
      return GetPrivateKeysResponse.standard(mmrpc: mmrpc, keys: standardKeys);
    }
  }

  final List<CoinKeyInfo>? standardKeys;
  final List<HdCoinKeyInfo>? hdKeys;

  /// Returns true if this response contains HD keys
  bool get isHdResponse => hdKeys != null;

  /// Returns true if this response contains standard keys
  bool get isStandardResponse => standardKeys != null;

  @override
  JsonMap toJson() {
    final result =
        isHdResponse
            ? hdKeys!.map((key) => key.toJson()).toList()
            : standardKeys!.map((key) => key.toJson()).toList();

    return {'mmrpc': mmrpc, 'result': result};
  }
}
