import 'dart:convert';
import 'dart:typed_data';

import 'package:eip712/eip712.dart' as eip712;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:test/test.dart';
import 'package:web3dart/web3dart.dart' as web3;

void main() {
  group('PrivateKeyExportTypedDataSigningStrategy', () {
    final credentials = web3.EthPrivateKey.fromInt(BigInt.one);
    final privateKey = KdfEvmPrivateKey(
      privateKeyHex: web3.bytesToHex(
        credentials.privateKey,
        include0x: true,
        padToEvenLength: true,
      ),
      address: credentials.address.with0x,
      assetId: kdfGnosisGasAssetId,
      derivationPath: "m/44'/60'/0'/0/0",
    );

    test(
      'signs EIP-712 typed data and recovers the selected address',
      () async {
        final strategy = PrivateKeyExportTypedDataSigningStrategy(
          clock: () => DateTime.utc(2026, 5, 26),
        );
        final request = _moduleTxRequest();

        final result = await strategy.signTypedData(
          request: request,
          privateKey: privateKey,
          expectedAddress: privateKey.address,
        );

        expect(result.signature, startsWith('0x'));
        expect(result.signature.length, 132);
        expect(result.signedAt, DateTime.utc(2026, 5, 26));
        expect(
          result.recoveredAddress?.toLowerCase(),
          privateKey.address.toLowerCase(),
        );
        expect(
          _recoverTypedDataSigner(
            request.typedDataJson,
            result.signature,
          ).toLowerCase(),
          privateKey.address.toLowerCase(),
        );
      },
    );

    test('rejects typed-data domain chain mismatch', () async {
      const strategy = PrivateKeyExportTypedDataSigningStrategy();

      await expectLater(
        strategy.signTypedData(
          request: _moduleTxRequest(chainId: 1),
          privateKey: privateKey,
          expectedAddress: privateKey.address,
        ),
        throwsA(
          isA<KdfSigningException>().having(
            (failure) => failure.code,
            'code',
            'chain_mismatch',
          ),
        ),
      );
    });

    test('rejects exported private-key address mismatches', () async {
      const strategy = PrivateKeyExportTypedDataSigningStrategy();

      await expectLater(
        strategy.signTypedData(
          request: _moduleTxRequest(),
          privateKey: KdfEvmPrivateKey(
            privateKeyHex: privateKey.privateKeyHex,
            address: '0x2222222222222222222222222222222222222222',
            assetId: privateKey.assetId,
          ),
          expectedAddress: privateKey.address,
        ),
        throwsA(
          isA<KdfSigningException>().having(
            (failure) => failure.code,
            'code',
            'exported_key_mismatch',
          ),
        ),
      );
    });

    test('redacts exported private key debug output', () {
      expect(privateKey.toString(), contains('<redacted>'));
      expect(privateKey.toString(), isNot(contains(privateKey.privateKeyHex)));
    });
  });

  group('KdfDexFundingRepository', () {
    test('uses configured Gnosis token asset IDs', () {
      expect(kdfGnosisSpendableTokenAssets['EURe'], 'EURE-GNO');
      expect(kdfGnosisSpendableTokenAssets['GBPe'], 'GBPE-GNO');
      expect(kdfGnosisSpendableTokenAssets['USDCe'], 'USDC-GNO');
      expect(kdfGnosisSpendableTokenAssets['USDC.e'], 'USDC-GNO');
    });

    test('rejects unsupported destination tokens before KDF startup', () async {
      final repository = KdfDexFundingRepository(sdk: KomodoDefiSdk());

      await expectLater(
        repository.quote(
          const KdfDexFundingQuoteRequest(
            source: KdfDexFundingSource(
              walletRef: 'wallet-local',
              addressRef: 'USDC-GNO:0x1111111111111111111111111111111111111111',
              address: '0x1111111111111111111111111111111111111111',
              assetId: 'USDC-GNO',
              chainId: kdfGnosisChainId,
              displaySymbol: 'USDC.e',
              balance: '100',
            ),
            sourceAmount: '10',
            destinationSafeAddress:
                '0x2222222222222222222222222222222222222222',
            destinationToken: 'DAI',
          ),
        ),
        throwsStateError,
      );
    });
  });
}

Eip712TypedDataRequest _moduleTxRequest({int chainId = kdfGnosisChainId}) {
  const safe = '0x3333333333333333333333333333333333333333';
  final typedData = {
    'types': {
      'EIP712Domain': [
        {'name': 'chainId', 'type': 'uint256'},
        {'name': 'verifyingContract', 'type': 'address'},
      ],
      'ModuleTx': [
        {'name': 'to', 'type': 'address'},
        {'name': 'value', 'type': 'uint256'},
        {'name': 'data', 'type': 'bytes'},
        {'name': 'operation', 'type': 'uint8'},
        {'name': 'nonce', 'type': 'uint256'},
      ],
    },
    'primaryType': 'ModuleTx',
    'domain': {'chainId': chainId, 'verifyingContract': safe},
    'message': {
      'to': '0x4444444444444444444444444444444444444444',
      'value': '0',
      'data': '0x',
      'operation': 0,
      'nonce': '1',
    },
  };
  return Eip712TypedDataRequest(
    typedDataJson: jsonEncode(typedData),
    chainId: chainId,
    verifyingContract: safe,
    primaryType: 'ModuleTx',
  );
}

String _recoverTypedDataSigner(String typedDataJson, String signature) {
  final typedData = eip712.TypedMessage.fromJson(
    Map<String, Object?>.from(jsonDecode(typedDataJson) as Map),
  );
  final digest = eip712.hashTypedData(
    typedData: typedData,
    version: eip712.TypedDataVersion.v4,
  );
  final bytes = web3.hexToBytes(signature);
  final msgSignature = web3.MsgSignature(
    web3.bytesToUnsignedInt(Uint8List.sublistView(bytes, 0, 32)),
    web3.bytesToUnsignedInt(Uint8List.sublistView(bytes, 32, 64)),
    bytes[64],
  );
  final publicKey = web3.ecRecover(digest, msgSignature);
  return web3.bytesToHex(web3.publicKeyToAddress(publicKey), include0x: true);
}
