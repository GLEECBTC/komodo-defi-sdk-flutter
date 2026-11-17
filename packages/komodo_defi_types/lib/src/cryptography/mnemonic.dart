import 'package:komodo_defi_types/src/utils/json_type_utils.dart';

class Mnemonic {
  // Authentication and RPC response models share this parser.

  /// Factory method to create Mnemonic from a RPC response
  factory Mnemonic.fromRpcJson(JsonMap result) {
    final format = result.value<String>('format');

    if (format == 'plaintext') {
      assert(
        result.value<dynamic>('mnemonic') is String,
        'Expected mnemonic to be a string',
      );

      return Mnemonic._(
        format: format,
        plaintextMnemonic: result.value<String>('mnemonic'),
      );
    } else if (format == 'encrypted') {
      return Mnemonic._(
        format: format,
        encryptedMnemonic: EncryptedMnemonicData.fromJson(
          result.value<JsonMap>('encrypted_mnemonic_data'),
        ),
      );
    } else {
      throw ArgumentError('Unsupported mnemonic format: $format');
    }
  }

  Mnemonic._({this.format, this.plaintextMnemonic, this.encryptedMnemonic});

  Mnemonic.plaintext(this.plaintextMnemonic)
    : format = 'plaintext',
      encryptedMnemonic = null;

  Mnemonic.encrypted(this.encryptedMnemonic)
    : format = 'encrypted',
      plaintextMnemonic = null;

  final String? format;
  final String? plaintextMnemonic;
  final EncryptedMnemonicData? encryptedMnemonic;

  bool get isEncrypted => encryptedMnemonic != null;

  // Convert Mnemonic to JSON
  JsonMap toJson() {
    final data = <String, dynamic>{};
    data['format'] = format;

    if (format == 'plaintext') {
      data['mnemonic'] = plaintextMnemonic;
    } else if (format == 'encrypted') {
      data['encrypted_mnemonic_data'] = encryptedMnemonic?.toJson();
    }

    return data;
  }

  static Mnemonic? tryParse(JsonMap json) {
    try {
      return Mnemonic.fromRpcJson(json);
    } catch (e) {
      return null;
    }
  }
}

class EncryptedMnemonicData {
  const EncryptedMnemonicData({
    required this.encryptionAlgorithm,
    required this.keyDerivationDetails,
    required this.iv,
    required this.ciphertext,
    required this.tag,
  });

  // Factory method to create EncryptedMnemonicData from JSON
  factory EncryptedMnemonicData.fromJson(JsonMap json) {
    return EncryptedMnemonicData(
      encryptionAlgorithm: json.value<String>('encryption_algorithm'),
      keyDerivationDetails: Argon2Details.fromJson(
        json.value<JsonMap>('key_derivation_details'),
      ),
      iv: json.value<String>('iv'),
      ciphertext: json.value<String>('ciphertext'),
      tag: json.value<String>('tag'),
    );
  }

  final String encryptionAlgorithm;
  final Argon2Details keyDerivationDetails;
  final String iv;
  final String ciphertext;
  final String tag;

  static EncryptedMnemonicData? tryParse(JsonMap json) {
    try {
      return EncryptedMnemonicData.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  // Example to show end-user for the correct format needed in the input
  static const JsonMap encryptedDataExample = {
    'encryption_algorithm': 'AES256CBC',
    'key_derivation_details': {
      'Argon2': {
        'params': {
          'algorithm': 'Argon2id',
          'version': '0x13',
          'm_cost': 65536,
          't_cost': 2,
          'p_cost': 1,
        },
        'salt_aes': 'w5bTRBnymFmaqoA54JAAyQ',
        'salt_hmac': 'icjb79YGPyLXOTYkJNEDgA',
      },
    },
    'iv': 'CyGHB/PJWa4Tp+j+F6FKxQ==',
    'ciphertext':
        '8XEB114+1hNhpsVfWrBakDYjjIoKu+W5T7CQVT6FImNS4Y2Y3BVTU677+'
        'bYPuGc59qt8ZSXeqpM0cQh2NGJYQ2qRY5WZTEOcqqUakNah3Jg=',
    'tag': '3P5vvw0+aid9VbCGmo8VyOZZn5vkGxFnTUFFeH51NJ0=',
  };

  // Convert EncryptedMnemonicData to JSON
  JsonMap toJson() {
    return {
      'encryption_algorithm': encryptionAlgorithm,
      'key_derivation_details': keyDerivationDetails.toJson(),
      'iv': iv,
      'ciphertext': ciphertext,
      'tag': tag,
    };
  }
}

class Argon2Details {
  Argon2Details({
    required this.algorithm,
    required this.version,
    required this.mCost,
    required this.tCost,
    required this.pCost,
    required this.saltAes,
    required this.saltHmac,
  });

  // Factory method to create Argon2Details from JSON
  factory Argon2Details.fromJson(JsonMap json) {
    var argon2Params = json;
    var argon2Salt = json;
    if (json['Argon2'] != null) {
      argon2Params = json.value<JsonMap>('Argon2', 'params');
      argon2Salt = json.value<JsonMap>('Argon2');
    }

    return Argon2Details(
      algorithm: argon2Params.value<String>('algorithm'),
      version: _parseVersion(argon2Params['version']),
      mCost: argon2Params.value<int>('m_cost'),
      tCost: argon2Params.value<int>('t_cost'),
      pCost: argon2Params.value<int>('p_cost'),
      saltAes: argon2Salt.value<String>('salt_aes'),
      saltHmac: argon2Salt.value<String>('salt_hmac'),
    );
  }

  final String algorithm;
  final int version;
  final int mCost;
  final int tCost;
  final int pCost;
  final String saltAes;
  final String saltHmac;

  static int _parseVersion(Object? value) {
    // dartify represents JS numbers as doubles on Wasm. Preserve integral
    // versions without relying on the platform's numeric string formatting.
    final parsed = switch (value) {
      int() => value,
      double() when value.isFinite && value == value.truncateToDouble() =>
        int.tryParse(value.toStringAsFixed(0)),
      String() => int.tryParse(value),
      _ => null,
    };
    if (parsed == null) {
      throw const FormatException('Invalid Argon2 version');
    }
    return parsed;
  }

  // Convert Argon2Details to JSON
  JsonMap toJson() {
    return {
      'algorithm': algorithm,
      'version': version,
      'm_cost': mCost,
      't_cost': tCost,
      'p_cost': pCost,
      'salt_aes': saltAes,
      'salt_hmac': saltHmac,
    };
  }
}
