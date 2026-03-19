import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

import 'hive/test_harness.dart';

Map<String, dynamic> _trxConfig() => {
  'coin': 'TRX',
  'type': 'TRX',
  'name': 'TRON',
  'fname': 'TRON',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'required_confirmations': 1,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRX',
    'protocol_data': {'network': 'Mainnet'},
  },
  'nodes': <Map<String, dynamic>>[],
};

Map<String, dynamic> _trc20Config({
  required String coin,
  required String name,
  required String contractAddress,
}) => {
  'coin': coin,
  'type': 'TRC-20',
  'name': name,
  'fname': name,
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRC20',
    'protocol_data': {'platform': 'TRX', 'contract_address': contractAddress},
  },
  'contract_address': contractAddress,
  'parent_coin': 'TRX',
  'nodes': <Map<String, dynamic>>[],
};

Asset _buildTrc20Asset({
  required Asset platformAsset,
  required String coin,
  required String name,
  required String contractAddress,
}) {
  return Asset.fromJson(
    _trc20Config(coin: coin, name: name, contractAddress: contractAddress),
    knownIds: {platformAsset.id},
  );
}

void main() {
  group('CustomTokenStorage', () {
    late HiveTestEnv hiveEnv;
    late CustomTokenStorage storage;
    late Asset platformAsset;

    setUp(() async {
      hiveEnv = HiveTestEnv();
      await hiveEnv.setup();
      storage = CustomTokenStorage(customTokensBoxName: 'custom_tokens_test');
      await storage.init();
      platformAsset = Asset.fromJson(_trxConfig(), knownIds: const {});
    });

    tearDown(() async {
      await storage.dispose();
      await hiveEnv.dispose();
    });

    test(
      'upsert allows replacing an existing token with the same contract',
      () async {
        final original = _buildTrc20Asset(
          platformAsset: platformAsset,
          coin: 'USDT-TRC20',
          name: 'Tether USD',
          contractAddress: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        );
        final updated = _buildTrc20Asset(
          platformAsset: platformAsset,
          coin: 'USDT-TRC20',
          name: 'Tether USD Updated',
          contractAddress: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        );

        await storage.storeCustomToken(original);
        final didUpdate = await storage.upsertCustomToken(updated);
        final stored = await storage.getCustomToken(updated.id);

        expect(didUpdate, isTrue);
        expect(stored?.id.name, updated.id.name);
        expect(
          stored?.protocol.contractAddress,
          updated.protocol.contractAddress,
        );
      },
    );

    test('store rejects same-id different-contract collisions', () async {
      final original = _buildTrc20Asset(
        platformAsset: platformAsset,
        coin: 'USDT-TRC20',
        name: 'Tether USD',
        contractAddress: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
      );
      final conflicting = _buildTrc20Asset(
        platformAsset: platformAsset,
        coin: 'USDT-TRC20',
        name: 'Another USDT',
        contractAddress: 'TXLAQ63Xg1NAzckPwKHvzw7CSEmLMEqcdj',
      );

      await storage.storeCustomToken(original);

      await expectLater(
        storage.storeCustomToken(conflicting),
        throwsA(isA<CustomTokenConflictException>()),
      );

      final stored = await storage.getCustomToken(original.id);
      expect(await storage.getCustomTokenCount(), 1);
      expect(
        stored?.protocol.contractAddress,
        original.protocol.contractAddress,
      );
    });

    test(
      'addCustomTokenIfNotExists is idempotent for the same contract',
      () async {
        final asset = _buildTrc20Asset(
          platformAsset: platformAsset,
          coin: 'USDT-TRC20',
          name: 'Tether USD',
          contractAddress: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        );

        final firstInsert = await storage.addCustomTokenIfNotExists(asset);
        final secondInsert = await storage.addCustomTokenIfNotExists(asset);

        expect(firstInsert, isTrue);
        expect(secondInsert, isFalse);
        expect(await storage.getCustomTokenCount(), 1);
      },
    );

    test(
      'storeCustomTokens fails atomically for conflicting batch entries',
      () async {
        final first = _buildTrc20Asset(
          platformAsset: platformAsset,
          coin: 'USDT-TRC20',
          name: 'Tether USD',
          contractAddress: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        );
        final conflicting = _buildTrc20Asset(
          platformAsset: platformAsset,
          coin: 'USDT-TRC20',
          name: 'Another USDT',
          contractAddress: 'TXLAQ63Xg1NAzckPwKHvzw7CSEmLMEqcdj',
        );

        await expectLater(
          storage.storeCustomTokens([first, conflicting]),
          throwsA(isA<CustomTokenConflictException>()),
        );

        expect(await storage.getCustomTokenCount(), 0);
        expect(await storage.getCustomToken(first.id), isNull);
      },
    );
  });
}
