import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

void main() {
  test('global Equatable stringification cannot disclose recovery secrets', () {
    final assetId = AssetId(
      id: 'TEST',
      name: 'Fixture',
      symbol: AssetSymbol(assetConfigId: 'TEST'),
      chainId: AssetChainId(chainId: 0, decimalsValue: 8),
      derivationPath: "m/44'/0'",
      subClass: CoinSubClass.utxo,
    );
    final key = PrivateKey(
      assetId: assetId,
      publicKeySecp256k1: 'public',
      publicKeyAddress: 'address',
      privateKey: 'SYNTHETIC_PRIVATE_SENTINEL',
      viewingKey: 'SYNTHETIC_VIEWING_SENTINEL',
    );
    final previous = EquatableConfig.stringify;
    EquatableConfig.stringify = true;
    try {
      expect(key.toString(), 'PrivateKey(redacted)');
      expect([key].toString(), isNot(contains('SYNTHETIC_')));
      expect(jsonEncode(key.toJson()), contains('SYNTHETIC_PRIVATE_SENTINEL'));
      expect(jsonEncode(key.toJson()), contains('SYNTHETIC_VIEWING_SENTINEL'));
    } finally {
      EquatableConfig.stringify = previous;
    }
  });
}
