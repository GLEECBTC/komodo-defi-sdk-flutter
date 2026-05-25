import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:komodo_coin_updates/hive/hive_registrar.g.dart';
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_coins/src/asset_filter.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

void main() {
  group('Asset filtering', () {
    final btcConfig = {
      'coin': 'BTC',
      'fname': 'Bitcoin',
      'chain_id': 0,
      'type': 'UTXO',
      'protocol': {'type': 'UTXO'},
      'is_testnet': false,
      'trezor_coin': 'Bitcoin',
    };

    final noTrezorConfig = {
      'coin': 'NTZ',
      'fname': 'NoTrezor',
      'chain_id': 1,
      'type': 'UTXO',
      'protocol': {'type': 'UTXO'},
      'is_testnet': false,
      // intentionally no 'trezor_coin'
    };

    final xdaiConfig = {
      'coin': 'XDAI',
      'fname': 'Gnosis',
      'chain_id': 100,
      'type': 'Gnosis',
      'protocol': {
        'type': 'ETH',
        'protocol_data': {'chain_id': 100},
      },
      'swap_contract_address': '0x0000000000000000000000000000000000000001',
      'fallback_swap_contract': '0x0000000000000000000000000000000000000001',
      'is_testnet': false,
      'nodes': [
        {'url': 'https://rpc.gnosischain.com'},
      ],
    };

    late CoinConfigRepository repo;
    // Use repository helpers to parse and store assets from raw JSON
    setUp(() async {
      Hive.init(
        './.dart_tool/test_hive_${DateTime.now().microsecondsSinceEpoch}',
      );
      try {
        Hive.registerAdapters();
      } catch (_) {}
      repo = CoinConfigRepository.withDefaults(
        const AssetRuntimeUpdateConfig(
          fetchAtBuildEnabled: false,
          updateCommitOnBuild: false,
          bundledCoinsRepoCommit: 'local',
          runtimeUpdatesEnabled: false,
          mappedFiles: {},
          mappedFolders: {},
          cdnBranchMirrors: {},
        ),
      );
      await repo.upsertRawAssets({
        'BTC': btcConfig,
        'NTZ': noTrezorConfig,
      }, 'test');
    });

    tearDown(() async {
      await Hive.close();
    });

    Future<Map<AssetId, Asset>> assetsFromRepo() async {
      final list = await repo.getAssets();
      return {for (final a in list) a.id: a};
    }

    test('Trezor filter excludes assets missing trezor_coin', () async {
      const filter = TrezorAssetFilterStrategy();
      final assets = await assetsFromRepo();
      final filtered = <AssetId, Asset>{};
      for (final entry in assets.entries) {
        if (filter.shouldInclude(entry.value, entry.value.protocol.config)) {
          filtered[entry.key] = entry.value;
        }
      }
      expect(filtered.keys.any((id) => id.id == 'BTC'), isTrue);
      expect(filtered.keys.any((id) => id.id == 'NTZ'), isFalse);
    });

    test('Trezor filter ignores empty trezor_coin field', () async {
      final cfg = Map<String, dynamic>.from(btcConfig)..['trezor_coin'] = '';
      final asset = Asset.fromJson(cfg);
      const filter = TrezorAssetFilterStrategy();
      expect(filter.shouldInclude(asset, asset.protocol.config), isFalse);
    });

    test('UTXO filter only includes utxo assets', () async {
      const filter = UtxoAssetFilterStrategy();
      final assets = await assetsFromRepo();
      final btc = assets.keys.firstWhere((id) => id.id == 'BTC');
      final ntz = assets.keys.firstWhere((id) => id.id == 'NTZ');
      expect(
        filter.shouldInclude(assets[btc]!, assets[btc]!.protocol.config),
        isTrue,
      );
      expect(
        filter.shouldInclude(assets[ntz]!, assets[ntz]!.protocol.config),
        isTrue,
      );
    });

    test('UTXO filter accepts smartChain subclass', () {
      final cfg = Map<String, dynamic>.from(btcConfig)
        ..['type'] = 'SMART_CHAIN'
        ..['protocol'] = {'type': 'UTXO'};
      final asset = Asset.fromJson(cfg);
      const filter = UtxoAssetFilterStrategy();
      expect(asset.protocol.subClass, CoinSubClass.smartChain);
      expect(filter.shouldInclude(asset, asset.protocol.config), isTrue);
    });

    test('EVM filter accepts Gnosis assets', () {
      final asset = Asset.fromJson(xdaiConfig);
      const filter = EvmAssetFilterStrategy();

      expect(asset.protocol.subClass, CoinSubClass.gnosis);
      expect(filter.shouldInclude(asset, asset.protocol.config), isTrue);
    });
  });
}
