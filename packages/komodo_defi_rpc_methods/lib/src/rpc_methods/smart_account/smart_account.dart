import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

const _eip712DomainFields = <Map<String, String>>[
  {'name': 'chainId', 'type': 'uint256'},
  {'name': 'verifyingContract', 'type': 'address'},
];
const _execTransactionFromModuleSelector = '468721a7';
const _erc20TransferSelector = 'a9059cbb';
const _setAllowanceSelector = 'a8ec43ee';
const _spendingAllowanceKey =
    'fe687fc128d1915040376d20ccb1bf40d838ddd82bf9b0ba3da683cc2a251623';

/// A user-requested operation to compare against Gnosis Pay typed data.
class SmartAccountRequestedAction {
  const SmartAccountRequestedAction._({
    required this.kind,
    required this.target,
    required this.amount,
    this.recipient,
    this.periodSeconds,
  });

  const SmartAccountRequestedAction.withdrawal({
    required String assetContract,
    required String recipient,
    required BigInt amount,
  }) : this._(
         kind: SmartAccountIntentKind.withdrawal,
         target: assetContract,
         recipient: recipient,
         amount: amount,
       );

  const SmartAccountRequestedAction.dailyLimit({
    required String bouncer,
    required BigInt amount,
    required int periodSeconds,
  }) : this._(
         kind: SmartAccountIntentKind.dailyLimit,
         target: bouncer,
         amount: amount,
         periodSeconds: periodSeconds,
       );

  final SmartAccountIntentKind kind;
  final String target;
  final String? recipient;
  final BigInt amount;
  final int? periodSeconds;
}

enum SmartAccountIntentKind { withdrawal, dailyLimit }

/// Fully decoded, immutable operation shown to the user before KDF is called.
class PreparedSmartAccountIntent {
  PreparedSmartAccountIntent._({
    required this.kind,
    required this.chainId,
    required this.safeAddress,
    required this.delayModule,
    required this.target,
    required this.amount,
    required this.payloadDigest,
    required Map<String, dynamic> typedData,
    this.recipient,
    this.periodSeconds,
  }) : _typedData = typedData;

  final SmartAccountIntentKind kind;
  final BigInt chainId;
  final String safeAddress;
  final String delayModule;
  final String target;
  final String? recipient;
  final BigInt amount;
  final int? periodSeconds;

  /// SHA-256 of canonical normalized JSON. This is an SDK mutation guard;
  /// KDF returns and signs the authoritative EIP-712 digest.
  final String payloadDigest;
  final Map<String, dynamic> _typedData;

  Map<String, dynamic> get typedData =>
      jsonDecode(jsonEncode(_typedData)) as Map<String, dynamic>;

  void requireMatches(SmartAccountRequestedAction requested) {
    if (requested.kind != kind ||
        _address(requested.target) != target ||
        requested.amount != amount ||
        (kind == SmartAccountIntentKind.withdrawal &&
            _address(requested.recipient ?? '') != recipient) ||
        (kind == SmartAccountIntentKind.dailyLimit &&
            requested.periodSeconds != periodSeconds)) {
      throw const SmartAccountIntentException(
        'The signed payload does not match the requested operation.',
      );
    }
  }
}

class SmartAccountIntentException implements Exception {
  const SmartAccountIntentException(this.message);
  final String message;

  @override
  String toString() => 'SmartAccountIntentException: $message';
}

/// Normalizes Account Kit payloads and decodes the operations KDF permits.
class SmartAccountIntentCodec {
  const SmartAccountIntentCodec();

  Map<String, dynamic> normalize(Map<String, dynamic> input) {
    final normalized = jsonDecode(jsonEncode(input)) as Map<String, dynamic>;
    _map(
      normalized['types'],
      'types',
    ).putIfAbsent('EIP712Domain', () => _eip712DomainFields);
    return normalized;
  }

  PreparedSmartAccountIntent prepare(
    Map<String, dynamic> input, {
    required String safeAddress,
    SmartAccountRequestedAction? requested,
  }) {
    final typedData = normalize(input);
    if (typedData['primaryType'] != 'ModuleTx') {
      throw const SmartAccountIntentException(
        'Only Gnosis Pay ModuleTx withdrawals and limit changes are supported.',
      );
    }
    _expectSchema(typedData);
    final domain = _map(typedData['domain'], 'domain');
    final message = _map(typedData['message'], 'message');
    final delay = _address(
      _string(domain['verifyingContract'], 'verifyingContract'),
    );
    final chainId = _uint(domain['chainId'], 'chainId');
    final outer = _decodeOuter(_hex(_string(message['data'], 'data')));
    if (outer.operation != BigInt.zero || outer.target == _zeroAddress) {
      throw const SmartAccountIntentException(
        'ModuleTx must call a non-zero target without delegatecall.',
      );
    }

    late final PreparedSmartAccountIntent prepared;
    final selector = _hexString(outer.data.take(4));
    if (outer.value > BigInt.zero && outer.data.isEmpty) {
      prepared = _prepared(
        kind: SmartAccountIntentKind.withdrawal,
        chainId: chainId,
        safe: safeAddress,
        delay: delay,
        target: _zeroAddress,
        recipient: outer.target,
        amount: outer.value,
        typedData: typedData,
      );
    } else if (outer.value == BigInt.zero &&
        selector == _erc20TransferSelector) {
      _requireLength(outer.data, 68, 'ERC-20 transfer');
      prepared = _prepared(
        kind: SmartAccountIntentKind.withdrawal,
        chainId: chainId,
        safe: safeAddress,
        delay: delay,
        target: outer.target,
        recipient: _wordAddress(outer.data, 4),
        amount: _wordUint(outer.data, 36),
        typedData: typedData,
      );
    } else if (outer.value == BigInt.zero &&
        selector == _setAllowanceSelector) {
      _requireLength(outer.data, 196, 'setAllowance');
      final key = _hexString(outer.data.sublist(4, 36));
      final balance = _wordUint(outer.data, 36);
      final maxRefill = _wordUint(outer.data, 68);
      final refill = _wordUint(outer.data, 100);
      final period = _wordUint(outer.data, 132);
      if (key != _spendingAllowanceKey ||
          balance <= BigInt.zero ||
          balance != maxRefill ||
          balance != refill ||
          period <= BigInt.zero ||
          period > BigInt.from(0x7fffffff)) {
        throw const SmartAccountIntentException(
          'The daily-limit payload is not in the canonical Gnosis Pay shape.',
        );
      }
      prepared = _prepared(
        kind: SmartAccountIntentKind.dailyLimit,
        chainId: chainId,
        safe: safeAddress,
        delay: delay,
        target: outer.target,
        amount: balance,
        periodSeconds: period.toInt(),
        typedData: typedData,
      );
    } else {
      throw const SmartAccountIntentException(
        'Unsupported Gnosis Pay module operation.',
      );
    }

    if (prepared.amount <= BigInt.zero || prepared.recipient == _zeroAddress) {
      throw const SmartAccountIntentException(
        'Operation recipient and amount must be non-zero.',
      );
    }
    if (requested != null) prepared.requireMatches(requested);
    return prepared;
  }

  PreparedSmartAccountIntent _prepared({
    required SmartAccountIntentKind kind,
    required BigInt chainId,
    required String safe,
    required String delay,
    required String target,
    required BigInt amount,
    required Map<String, dynamic> typedData,
    String? recipient,
    int? periodSeconds,
  }) {
    final canonical = _canonicalJson(typedData);
    return PreparedSmartAccountIntent._(
      kind: kind,
      chainId: chainId,
      safeAddress: _address(safe),
      delayModule: delay,
      target: _address(target),
      recipient: recipient == null ? null : _address(recipient),
      amount: amount,
      periodSeconds: periodSeconds,
      payloadDigest: sha256.convert(utf8.encode(canonical)).toString(),
      typedData: typedData,
    );
  }

  void _expectSchema(Map<String, dynamic> typedData) {
    final types = _map(typedData['types'], 'types');
    const expected = <Map<String, String>>[
      {'name': 'data', 'type': 'bytes'},
      {'name': 'salt', 'type': 'bytes32'},
    ];
    if (jsonEncode(types['ModuleTx']) != jsonEncode(expected) ||
        jsonEncode(types['EIP712Domain']) != jsonEncode(_eip712DomainFields)) {
      throw const SmartAccountIntentException('Unexpected EIP-712 schema.');
    }
  }
}

class _OuterCall {
  const _OuterCall({
    required this.target,
    required this.value,
    required this.data,
    required this.operation,
  });
  final String target;
  final BigInt value;
  final Uint8List data;
  final BigInt operation;
}

_OuterCall _decodeOuter(Uint8List bytes) {
  if (bytes.length < 164 ||
      _hexString(bytes.take(4)) != _execTransactionFromModuleSelector) {
    throw const SmartAccountIntentException('Invalid ModuleTx calldata.');
  }
  final offset = _wordUint(bytes, 68).toInt();
  final dynamicStart = 4 + offset;
  if (offset != 128 || dynamicStart + 32 > bytes.length) {
    throw const SmartAccountIntentException('Non-canonical ModuleTx calldata.');
  }
  final length = _wordUint(bytes, dynamicStart).toInt();
  final dataStart = dynamicStart + 32;
  final paddedLength = ((length + 31) ~/ 32) * 32;
  if (dataStart + paddedLength != bytes.length) {
    throw const SmartAccountIntentException(
      'Malformed ModuleTx inner calldata.',
    );
  }
  return _OuterCall(
    target: _wordAddress(bytes, 4),
    value: _wordUint(bytes, 36),
    data: Uint8List.fromList(bytes.sublist(dataStart, dataStart + length)),
    operation: _wordUint(bytes, 100),
  );
}

class RegisterSmartAccountRequest
    extends BaseRequest<RegisterSmartAccountResponse, GeneralErrorResponse> {
  RegisterSmartAccountRequest({
    required String rpcPass,
    required this.coin,
    required this.safeAddress,
    this.from,
  }) : super(
         method: 'smart_account::register',
         rpcPass: rpcPass,
         mmrpc: RpcVersion.v2_0,
       );

  final String coin;
  final String safeAddress;
  final AddressPath? from;

  @override
  Map<String, dynamic> toJson() => super.toJson().deepMerge({
    'params': {
      'coin': coin,
      'safe_address': safeAddress,
      if (from != null) 'from': from!.toJson(),
    },
  });

  @override
  RegisterSmartAccountResponse parse(Map<String, dynamic> json) =>
      RegisterSmartAccountResponse.parse(json);
}

class RegisterSmartAccountResponse extends BaseResponse {
  RegisterSmartAccountResponse({
    required super.mmrpc,
    required this.coin,
    required this.ownerAddress,
    required this.smartAccountAddress,
  });

  factory RegisterSmartAccountResponse.parse(Map<String, dynamic> json) {
    final result = json.value<JsonMap>('result');
    return RegisterSmartAccountResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      coin: result.value<String>('coin'),
      ownerAddress: result.value<String>('owner_address'),
      smartAccountAddress: result.value<String>('smart_account_address'),
    );
  }

  final String coin;
  final String ownerAddress;
  final String smartAccountAddress;

  @override
  Map<String, dynamic> toJson() => {
    'mmrpc': mmrpc,
    'result': {
      'coin': coin,
      'owner_address': ownerAddress,
      'smart_account_address': smartAccountAddress,
    },
  };
}

class SignSmartAccountTypedDataRequest
    extends
        BaseRequest<SignSmartAccountTypedDataResponse, GeneralErrorResponse> {
  SignSmartAccountTypedDataRequest({
    required String rpcPass,
    required this.coin,
    required this.intent,
    this.from,
  }) : super(
         method: 'smart_account::sign_typed_data',
         rpcPass: rpcPass,
         mmrpc: RpcVersion.v2_0,
       );

  final String coin;
  final PreparedSmartAccountIntent intent;
  final AddressPath? from;

  @override
  Map<String, dynamic> toJson() => super.toJson().deepMerge({
    'params': {
      'coin': coin,
      'typed_data': intent.typedData,
      if (from != null) 'from': from!.toJson(),
    },
  });

  @override
  SignSmartAccountTypedDataResponse parse(Map<String, dynamic> json) =>
      SignSmartAccountTypedDataResponse.parse(json);
}

class SignSmartAccountTypedDataResponse extends BaseResponse {
  SignSmartAccountTypedDataResponse({
    required super.mmrpc,
    required this.ownerAddress,
    required this.verifyingContract,
    required this.typedDataHash,
    required this.signature,
  });

  factory SignSmartAccountTypedDataResponse.parse(Map<String, dynamic> json) {
    final result = json.value<JsonMap>('result');
    return SignSmartAccountTypedDataResponse(
      mmrpc: json.valueOrNull<String>('mmrpc'),
      ownerAddress: result.value<String>('owner_address'),
      verifyingContract: result.value<String>('verifying_contract'),
      typedDataHash: result.value<String>('typed_data_hash'),
      signature: result.value<String>('signature'),
    );
  }

  final String ownerAddress;
  final String verifyingContract;
  final String typedDataHash;
  final String signature;

  @override
  Map<String, dynamic> toJson() => {
    'mmrpc': mmrpc,
    'result': {
      'owner_address': ownerAddress,
      'verifying_contract': verifyingContract,
      'typed_data_hash': typedDataHash,
      'signature': signature,
    },
  };
}

Map<String, dynamic> _map(Object? value, String name) {
  if (value is Map<String, dynamic>) return value;
  throw SmartAccountIntentException('$name must be an object.');
}

String _string(Object? value, String name) {
  if (value is String) return value;
  throw SmartAccountIntentException('$name must be a string.');
}

BigInt _uint(Object? value, String name) {
  if (value is int && value >= 0) return BigInt.from(value);
  if (value is String) {
    final source = value.toLowerCase();
    final parsed = source.startsWith('0x')
        ? BigInt.tryParse(source.substring(2), radix: 16)
        : BigInt.tryParse(source);
    if (parsed != null && parsed >= BigInt.zero) return parsed;
  }
  throw SmartAccountIntentException('$name must be an unsigned integer.');
}

Uint8List _hex(String value) {
  final source = value.startsWith('0x') ? value.substring(2) : value;
  if (source.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(source)) {
    throw const SmartAccountIntentException('Invalid hexadecimal calldata.');
  }
  return Uint8List.fromList([
    for (var i = 0; i < source.length; i += 2)
      int.parse(source.substring(i, i + 2), radix: 16),
  ]);
}

String _address(String value) {
  final source = value.toLowerCase();
  if (!RegExp(r'^0x[0-9a-f]{40}$').hasMatch(source)) {
    throw SmartAccountIntentException('Invalid EVM address: $value');
  }
  return source;
}

const _zeroAddress = '0x0000000000000000000000000000000000000000';

String _wordAddress(Uint8List bytes, int offset) =>
    _address('0x${_hexString(bytes.sublist(offset + 12, offset + 32))}');

BigInt _wordUint(Uint8List bytes, int offset) {
  if (offset < 0 || offset + 32 > bytes.length) {
    throw const SmartAccountIntentException('Calldata word is out of bounds.');
  }
  return BigInt.parse(
    _hexString(bytes.sublist(offset, offset + 32)),
    radix: 16,
  );
}

String _hexString(Iterable<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

void _requireLength(Uint8List bytes, int expected, String operation) {
  if (bytes.length != expected) {
    throw SmartAccountIntentException('Malformed $operation calldata.');
  }
}

String _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    final entries = keys.map(
      (key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}',
    );
    return '{${entries.join(',')}}';
  }
  if (value is List) return '[${value.map(_canonicalJson).join(',')}]';
  return jsonEncode(value);
}
