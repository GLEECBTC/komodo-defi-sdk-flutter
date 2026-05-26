// ignore_for_file: document_ignores
// ignore_for_file: one_member_abstracts, public_member_api_docs

import 'dart:convert';
import 'dart:typed_data';

import 'package:eip712/eip712.dart' as eip712;
import 'package:komodo_defi_sdk/src/kdf/kdf_evm_account_repository.dart';
import 'package:web3dart/web3dart.dart' as web3;

final class Eip712TypedDataRequest {
  const Eip712TypedDataRequest({
    required this.typedDataJson,
    required this.chainId,
    required this.verifyingContract,
    required this.primaryType,
  });

  final String typedDataJson;
  final int chainId;
  final String verifyingContract;
  final String primaryType;
}

final class Eip712SigningResult {
  const Eip712SigningResult({
    required this.signature,
    required this.signedAt,
    this.recoveredAddress,
  });

  final String signature;
  final DateTime signedAt;
  final String? recoveredAddress;
}

final class KdfSigningException implements Exception {
  const KdfSigningException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => 'KdfSigningException($code): $message';
}

abstract interface class TypedDataSigningStrategy {
  Future<Eip712SigningResult> signTypedData({
    required Eip712TypedDataRequest request,
    required KdfEvmPrivateKey privateKey,
    required String expectedAddress,
  });
}

final class PrivateKeyExportTypedDataSigningStrategy
    implements TypedDataSigningStrategy {
  const PrivateKeyExportTypedDataSigningStrategy({
    DateTime Function()? clock,
    int requiredChainId = kdfGnosisChainId,
  }) : _clock = clock,
       _requiredChainId = requiredChainId;

  final DateTime Function()? _clock;
  final int _requiredChainId;

  Future<Eip712SigningResult> signPersonalMessage({
    required String message,
    required KdfEvmPrivateKey privateKey,
    required String expectedAddress,
  }) async {
    _requireSameAddress(
      privateKey.address,
      expectedAddress,
      code: 'exported_key_mismatch',
      message: 'Exported KDF private key address does not match account.',
    );
    final credentials = web3.EthPrivateKey.fromHex(privateKey.privateKeyHex);
    _requireSameAddress(
      credentials.address.with0x,
      expectedAddress,
      code: 'private_key_mismatch',
      message: 'Private key does not derive the selected account address.',
    );
    final signature = credentials.signPersonalMessageToUint8List(
      Uint8List.fromList(utf8.encode(message)),
    );
    return Eip712SigningResult(
      signature: web3.bytesToHex(signature, include0x: true),
      signedAt: _now(),
      recoveredAddress: expectedAddress,
    );
  }

  @override
  Future<Eip712SigningResult> signTypedData({
    required Eip712TypedDataRequest request,
    required KdfEvmPrivateKey privateKey,
    required String expectedAddress,
  }) async {
    _requireSameAddress(
      privateKey.address,
      expectedAddress,
      code: 'exported_key_mismatch',
      message: 'Exported KDF private key address does not match account.',
    );
    final credentials = web3.EthPrivateKey.fromHex(privateKey.privateKeyHex);
    _requireSameAddress(
      credentials.address.with0x,
      expectedAddress,
      code: 'private_key_mismatch',
      message: 'Private key does not derive the selected account address.',
    );
    final message = _parseTypedData(request);
    final digest = eip712.hashTypedData(
      typedData: message,
      version: eip712.TypedDataVersion.v4,
    );
    final signature = web3.sign(
      digest,
      web3.hexToBytes(privateKey.privateKeyHex),
    );
    final recoveredAddress = _recoverAddress(digest, signature);
    _requireSameAddress(
      recoveredAddress,
      expectedAddress,
      code: 'signer_mismatch',
      message: 'Recovered typed-data signer does not match selected account.',
    );

    return Eip712SigningResult(
      signature: _encodeSignature(signature),
      signedAt: _now(),
      recoveredAddress: recoveredAddress,
    );
  }

  DateTime _now() => (_clock ?? DateTime.now).call().toUtc();

  eip712.TypedMessage _parseTypedData(Eip712TypedDataRequest request) {
    final decoded = _decodeTypedDataJson(request.typedDataJson);
    final domain = _domain(decoded);
    final domainChainId = _chainId(domain['chainId']);
    final verifyingContract = domain['verifyingContract'] as String?;
    final primaryType = decoded['primaryType'] as String?;

    if (request.chainId != _requiredChainId ||
        domainChainId != _requiredChainId) {
      throw const KdfSigningException(
        code: 'chain_mismatch',
        message: 'EIP-712 domain chainId must match the required EVM chain.',
      );
    }
    if (primaryType != request.primaryType) {
      throw const KdfSigningException(
        code: 'primary_type_mismatch',
        message: 'EIP-712 primaryType does not match the signing request.',
      );
    }
    _requireSameAddress(
      verifyingContract,
      request.verifyingContract,
      code: 'verifying_contract_mismatch',
      message:
          'EIP-712 domain verifyingContract does not match '
          'the signing request.',
    );

    try {
      final typedData = Map<String, Object?>.from(decoded);
      return eip712.TypedMessage.fromJson(typedData);
    } on Object {
      throw const KdfSigningException(
        code: 'typed_data_invalid',
        message: 'EIP-712 typed data is malformed or unsupported.',
      );
    }
  }

  Map<String, dynamic> _decodeTypedDataJson(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Mapped to KdfSigningException below.
    }
    throw const KdfSigningException(
      code: 'typed_data_invalid',
      message: 'EIP-712 typed data must be a JSON object.',
    );
  }

  Map<String, dynamic> _domain(Map<String, dynamic> decoded) {
    final domain = decoded['domain'];
    if (domain is Map<String, dynamic>) return domain;
    throw const KdfSigningException(
      code: 'typed_data_invalid',
      message: 'EIP-712 typed data must include a domain object.',
    );
  }

  int? _chainId(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  void _requireSameAddress(
    String? actual,
    String expected, {
    required String code,
    required String message,
  }) {
    if (actual == null ||
        actual.trim().toLowerCase() != expected.trim().toLowerCase()) {
      throw KdfSigningException(code: code, message: message);
    }
  }

  String _recoverAddress(Uint8List digest, web3.MsgSignature signature) {
    final publicKey = web3.ecRecover(digest, signature);
    return web3.bytesToHex(web3.publicKeyToAddress(publicKey), include0x: true);
  }

  String _encodeSignature(web3.MsgSignature signature) {
    final r = web3.padUint8ListTo32(web3.unsignedIntToBytes(signature.r));
    final s = web3.padUint8ListTo32(web3.unsignedIntToBytes(signature.s));
    final v = Uint8List.fromList([signature.v]);
    return web3.bytesToHex(
      Uint8List.fromList([...r, ...s, ...v]),
      include0x: true,
    );
  }
}
