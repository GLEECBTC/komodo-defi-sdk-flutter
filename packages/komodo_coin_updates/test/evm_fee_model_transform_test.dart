import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'hive/test_harness.dart';

Map<String, dynamic> config(int chain, {String type = 'ETH'}) => {
  'coin': 'ETH-BASE',
  'fname': 'Base',
  'type': type == 'ETH' ? 'Base' : 'ERC20',
  'chain_id': chain,
  'decimals': 18,
  'is_testnet': false,
  'swap_contract_address': '0x0000000000000000000000000000000000000001',
  'fallback_swap_contract': '0x0000000000000000000000000000000000000002',
  'nodes': [
    {'url': 'https://example.com'},
  ],
  'protocol': {
    'type': type,
    'protocol_data': {'chain_id': chain},
  },
};

class Bundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
    Uint8List.fromList(utf8.encode(jsonEncode({'ETH-BASE': config(8453)}))),
  );
}

void main() {
  const transform = EvmFeeModelTransform();
  test(
    'missing native models are filled once and explicit settings preserved',
    () {
      for (final pair in [
        (8453, 'op_stack'),
        (5000, 'mantle'),
        (143, 'monad'),
        (43114, 'avalanche'),
      ]) {
        final input = config(pair.$1);
        final result = transform.transform(input);
        expect(input, isNot(contains('fee_model')));
        expect(result['fee_model'], pair.$2);
        expect(transform.needsTransform(result), isFalse);
        expect(transform.transform(result), result);
        expect(
          transform.transform({...input, 'fee_model': 'custom'})['fee_model'],
          'custom',
        );
      }
      expect(transform.needsTransform(config(1)), isFalse);
      expect(transform.needsTransform(config(42161)), isFalse);
      expect(transform.needsTransform(config(8453, type: 'ERC20')), isFalse);
    },
  );
  test(
    'bundled, refreshed and cached startup apply the default transform',
    () async {
      final env = HiveTestEnv();
      await env.setup();
      addTearDown(env.dispose);
      final local = LocalAssetCoinConfigProvider(
        packageName: 'test',
        coinsConfigAssetPath: 'coins.json',
        bundledCommit: 'pinned',
        bundle: Bundle(),
      );
      final bundled = await local.getAssets();
      expect(bundled.single.protocol.config['fee_model'], 'op_stack');
      final remote = GithubCoinConfigProvider(
        branch: 'master',
        coinsGithubContentUrl: 'https://example.com/coins',
        coinsGithubApiUrl: 'https://example.com/api',
        coinsPath: 'coins',
        coinsConfigPath: 'config.json',
        httpClient: MockClient(
          (request) async =>
              http.Response(jsonEncode({'ETH-BASE': config(8453)}), 200),
        ),
      );
      final refreshed = await remote.getAssetsForCommit('pinned');
      expect(refreshed.single.protocol.config['fee_model'], 'op_stack');
      final repository = CoinConfigRepository(coinConfigProvider: local);
      // Write raw pre-upgrade data, then simulate a cold cached startup.
      await repository.upsertRawAssets({'ETH-BASE': config(8453)}, 'pinned');
      await env.restart();
      final restarted = CoinConfigRepository(coinConfigProvider: local);
      final cached = await restarted.getAssets();
      expect(cached.single.protocol.config['fee_model'], 'op_stack');
      expect(
        (await restarted.getAsset(
          cached.single.id,
        ))!.protocol.config['fee_model'],
        'op_stack',
      );
      expect(await restarted.getCurrentCommit(), 'pinned');
    },
  );
}
