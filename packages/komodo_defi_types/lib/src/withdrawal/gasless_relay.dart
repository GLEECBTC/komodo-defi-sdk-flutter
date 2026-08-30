import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

const Set<String> _signedAuthorizationKeys = {
  'token',
  'service_provider',
  'user',
  'receiver',
  'value',
  'max_fee',
  'deadline',
  'version',
  'nonce',
  'sig',
};

const Set<String> _relayPayloadKeys = {
  'relay_type',
  'chain_id',
  'coin',
  'hd_from',
  'from_address',
  'gasfree_address',
  'verifying_contract',
  'signed_authorization',
  'created_at',
};

final RegExp _rfc3339Timestamp = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'
  r'(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
);
final RegExp _unsignedDecimal = RegExp(r'^[0-9]+$');
final RegExp _tronSignature = RegExp(r'^[0-9a-fA-F]{130}$');

void _rejectUnknownKeys(
  JsonMap json,
  Set<String> allowed, {
  required String context,
}) {
  final unknown = json.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException(
      '$context contains unknown fields: ${unknown.join(', ')}',
    );
  }
}

String _requiredString(JsonMap json, String key) {
  final value = json.value<String>(key);
  if (value.trim().isEmpty) {
    throw FormatException('$key must not be empty');
  }
  return value;
}

String _requiredUnsigned256String(JsonMap json, String key) {
  final value = _requiredString(json, key);
  final parsed = _unsignedDecimal.hasMatch(value)
      ? BigInt.tryParse(value)
      : null;
  if (parsed == null || parsed > _maximumUnsigned256) {
    throw FormatException('$key must be an unsigned U256 decimal string');
  }
  return value;
}

Object? _freezeJsonValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_freezeJsonValue));
  }
  if (value is Map) {
    final frozen = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const FormatException('JSON object keys must be strings');
      }
      frozen[key] = _freezeJsonValue(entry.value);
    }
    return Map<String, Object?>.unmodifiable(frozen);
  }
  throw FormatException('Unsupported JSON value: ${value.runtimeType}');
}

Object? _copyJsonValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is List) {
    return <Object?>[for (final item in value) _copyJsonValue(item)];
  }
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key as String: _copyJsonValue(entry.value),
    };
  }
  throw FormatException('Unsupported JSON value: ${value.runtimeType}');
}

JsonMap _freezeJsonMap(JsonMap value) => _freezeJsonValue(value)! as JsonMap;

JsonMap _copyJsonMap(JsonMap value) => _copyJsonValue(value)! as JsonMap;

/// Exact signed TIP-712 authorization returned in a GasFree withdraw preview.
///
/// Numeric authorization fields are strings on the KDF wire. [deadline] is
/// exposed as a [BigInt] because KDF represents it as an unsigned 256-bit
/// integer and Dart Web cannot exactly represent that domain with [int].
class GaslessSignedAuthorization extends Equatable {
  factory GaslessSignedAuthorization({
    required String token,
    required String serviceProvider,
    required String user,
    required String receiver,
    required String value,
    required String maxFee,
    required BigInt deadline,
    required String version,
    required String nonce,
    required String signature,
  }) => GaslessSignedAuthorization.fromJson({
    'token': token,
    'service_provider': serviceProvider,
    'user': user,
    'receiver': receiver,
    'value': value,
    'max_fee': maxFee,
    'deadline': deadline.toString(),
    'version': version,
    'nonce': nonce,
    'sig': signature,
  });

  const GaslessSignedAuthorization._({
    required this.token,
    required this.serviceProvider,
    required this.user,
    required this.receiver,
    required this.value,
    required this.maxFee,
    required this.deadline,
    required this.version,
    required this.nonce,
    required this.signature,
  });

  factory GaslessSignedAuthorization.fromJson(JsonMap json) {
    _rejectUnknownKeys(
      json,
      _signedAuthorizationKeys,
      context: 'GasFree signed authorization',
    );
    final deadline = BigInt.parse(_requiredUnsigned256String(json, 'deadline'));
    if (deadline <= BigInt.zero) {
      throw const FormatException(
        'GasFree authorization deadline must be a positive U256 integer',
      );
    }
    final version = _requiredString(json, 'version');
    if (version != '1') {
      throw const FormatException(
        'GasFree authorization version must be exactly 1',
      );
    }
    final signature = _requiredString(json, 'sig');
    if (!_tronSignature.hasMatch(signature)) {
      throw const FormatException(
        'GasFree authorization signature must be 65-byte unprefixed hex',
      );
    }
    return GaslessSignedAuthorization._(
      token: _requiredString(json, 'token'),
      serviceProvider: _requiredString(json, 'service_provider'),
      user: _requiredString(json, 'user'),
      receiver: _requiredString(json, 'receiver'),
      value: _requiredUnsigned256String(json, 'value'),
      maxFee: _requiredUnsigned256String(json, 'max_fee'),
      deadline: deadline,
      version: version,
      nonce: _requiredUnsigned256String(json, 'nonce'),
      signature: signature,
    );
  }

  final String token;
  final String serviceProvider;
  final String user;
  final String receiver;

  /// Token amount in base units.
  final String value;

  /// Signed fee cap in token base units.
  final String maxFee;

  /// Unix timestamp in seconds.
  final BigInt deadline;

  /// TIP-712 permit version. KDF currently requires exactly `1`.
  final String version;
  final String nonce;
  final String signature;

  /// Expiry as a UTC [DateTime], or `null` when outside Dart's date range.
  DateTime? get expiresAt {
    if (deadline > _maximumDateTimeEpochSeconds) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      deadline.toInt() * Duration.millisecondsPerSecond,
      isUtc: true,
    );
  }

  bool isExpiredAt(DateTime instant) =>
      deadline <=
      BigInt.from(
        instant.toUtc().millisecondsSinceEpoch ~/
            Duration.millisecondsPerSecond,
      );

  JsonMap toJson() => {
    'token': token,
    'service_provider': serviceProvider,
    'user': user,
    'receiver': receiver,
    'value': value,
    'max_fee': maxFee,
    'deadline': deadline.toString(),
    'version': version,
    'nonce': nonce,
    'sig': signature,
  };

  @override
  List<Object?> get props => [
    token,
    serviceProvider,
    user,
    receiver,
    value,
    maxFee,
    deadline,
    version,
    nonce,
    signature,
  ];

  @override
  String toString() =>
      'GaslessSignedAuthorization('
      'token: $token, serviceProvider: $serviceProvider, user: $user, '
      'receiver: $receiver, value: $value, maxFee: $maxFee, '
      'deadline: $deadline, version: $version, nonce: $nonce, '
      'signature: <redacted>)';
}

final BigInt _maximumUnsigned256 = (BigInt.one << 256) - BigInt.one;
final BigInt _maximumDateTimeEpochSeconds = BigInt.from(8640000000000);

/// Exact KDF relay payload passed verbatim to `send_raw_transaction`.
class TronGasfreeRelayPayload extends Equatable {
  TronGasfreeRelayPayload({
    required this.chainId,
    required this.coin,
    required this.fromAddress,
    required this.gasfreeAddress,
    required this.verifyingContract,
    required this.signedAuthorization,
    required this.createdAt,
    JsonMap? hdFrom,
  }) : hdFrom = hdFrom == null ? null : _freezeJsonMap(hdFrom);

  factory TronGasfreeRelayPayload.fromJson(JsonMap json) {
    _rejectUnknownKeys(
      json,
      _relayPayloadKeys,
      context: 'GasFree relay payload',
    );
    final relayType = _requiredString(json, 'relay_type');
    if (relayType != relayTypeValue) {
      throw FormatException('Unknown GasFree relay type: $relayType');
    }
    final createdAt = _requiredString(json, 'created_at');
    if (!_rfc3339Timestamp.hasMatch(createdAt) ||
        DateTime.tryParse(createdAt) == null) {
      throw const FormatException(
        'GasFree relay created_at must be an RFC3339 timestamp',
      );
    }

    return TronGasfreeRelayPayload(
      chainId: _requiredString(json, 'chain_id'),
      coin: _requiredString(json, 'coin'),
      hdFrom: json.valueOrNull<JsonMap>('hd_from'),
      fromAddress: _requiredString(json, 'from_address'),
      gasfreeAddress: _requiredString(json, 'gasfree_address'),
      verifyingContract: _requiredString(json, 'verifying_contract'),
      signedAuthorization: GaslessSignedAuthorization.fromJson(
        json.value<JsonMap>('signed_authorization'),
      ),
      createdAt: createdAt,
    );
  }

  static const String relayTypeValue = 'tron_gasfree';

  String get relayType => relayTypeValue;
  final String chainId;
  final String coin;

  /// Deeply immutable snapshot of the optional KDF derivation selector.
  final JsonMap? hdFrom;
  final String fromAddress;
  final String gasfreeAddress;
  final String verifyingContract;
  final GaslessSignedAuthorization signedAuthorization;
  final String createdAt;

  JsonMap toJson() => {
    'relay_type': relayTypeValue,
    'chain_id': chainId,
    'coin': coin,
    if (hdFrom != null) 'hd_from': _copyJsonMap(hdFrom!),
    'from_address': fromAddress,
    'gasfree_address': gasfreeAddress,
    'verifying_contract': verifyingContract,
    'signed_authorization': signedAuthorization.toJson(),
    'created_at': createdAt,
  };

  @override
  List<Object?> get props => [
    chainId,
    coin,
    hdFrom,
    fromAddress,
    gasfreeAddress,
    verifyingContract,
    signedAuthorization,
    createdAt,
  ];
}
