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
  });

  group('Trezor filter on the Gleec EVM chain', () {
    // GLEEC and KMD-GRC20 as coins_config.json lists them, plus the
    // trezor_coin that Trezor support requires.
    Map<String, dynamic> gleecConfig({String? trezorCoin = 'Gleec'}) => {
      'coin': 'GLEEC',
      'type': 'GRC-20',
      'name': 'Gleec',
      'fname': 'Gleec',
      'is_testnet': false,
      'mm2': 1,
      'chain_id': 11169,
      'required_confirmations': 3,
      'protocol': {
        'type': 'ETH',
        'protocol_data': {'chain_id': 11169},
      },
      'derivation_path': "m/44'/60'",
      'swap_contract_address': '0x51d9EfFc20F6965bc8DFD37E797ac52a72fcdb9D',
      'fallback_swap_contract': '0x51d9EfFc20F6965bc8DFD37E797ac52a72fcdb9D',
      'nodes': [
        {
          'url': 'https://evm-rpc.gleec.com',
          'ws_url': 'wss://evm-ws.gleec.com',
        },
      ],
      if (trezorCoin != null) 'trezor_coin': trezorCoin,
    };

    Map<String, dynamic> grc20Config({
      String? trezorCoin = 'Komodo (grc20)',
    }) => {
      'coin': 'KMD-GRC20',
      'type': 'GRC-20',
      'name': 'Komodo',
      'fname': 'Komodo',
      'is_testnet': false,
      'mm2': 1,
      'chain_id': 11169,
      'decimals': 18,
      'required_confirmations': 3,
      'protocol': {
        'type': 'ERC20',
        'protocol_data': {
          'platform': 'GLEEC',
          'contract_address': '0x3341acA97C71E12A80D1e01D8c86bE93ba669752',
        },
      },
      'derivation_path': "m/44'/60'",
      'contract_address': '0x3341acA97C71E12A80D1e01D8c86bE93ba669752',
      'parent_coin': 'GLEEC',
      'swap_contract_address': '0x51d9EfFc20F6965bc8DFD37E797ac52a72fcdb9D',
      'fallback_swap_contract': '0x51d9EfFc20F6965bc8DFD37E797ac52a72fcdb9D',
      'nodes': [
        {
          'url': 'https://evm-rpc.gleec.com',
          'ws_url': 'wss://evm-ws.gleec.com',
        },
      ],
      if (trezorCoin != null) 'trezor_coin': trezorCoin,
    };

    ({Asset platform, Asset token}) parse({
      String? platformTrezorCoin = 'Gleec',
      String? tokenTrezorCoin = 'Komodo (grc20)',
    }) {
      final platform = Asset.fromJson(
        gleecConfig(trezorCoin: platformTrezorCoin),
        knownIds: const {},
      );
      final token = Asset.fromJson(
        grc20Config(trezorCoin: tokenTrezorCoin),
        knownIds: {platform.id},
      );
      return (platform: platform, token: token);
    }

    bool include(Asset asset, [AssetFilterStrategy? filter]) =>
        (filter ?? const TrezorAssetFilterStrategy()).shouldInclude(
          asset,
          asset.protocol.config,
        );

    test('fixture parses as a GRC-20 platform and its token', () {
      final (:platform, :token) = parse();
      expect(platform.protocol.subClass, CoinSubClass.grc20);
      expect(platform.id.parentId, isNull);
      expect(token.protocol.subClass, CoinSubClass.grc20);
      expect(token.id.parentId, platform.id);
    });

    test('includes GLEEC and a GRC-20 token that name a trezor_coin', () {
      final (:platform, :token) = parse();
      expect(include(platform), isTrue);
      expect(include(token), isTrue);
    });

    test('excludes GLEEC and a GRC-20 token without a trezor_coin', () {
      final (:platform, :token) = parse(
        platformTrezorCoin: null,
        tokenTrezorCoin: null,
      );
      expect(include(platform), isFalse);
      expect(include(token), isFalse);
    });

    test('excludes GLEEC and a GRC-20 token with an empty trezor_coin', () {
      final (:platform, :token) = parse(
        platformTrezorCoin: '',
        tokenTrezorCoin: '',
      );
      expect(include(platform), isFalse);
      expect(include(token), isFalse);
    });

    test('hiddenAssets still hides GLEEC', () {
      final (:platform, token: _) = parse();
      const filter = TrezorAssetFilterStrategy(hiddenAssets: {'GLEEC'});
      expect(include(platform, filter), isFalse);
    });

    test('keeps every other EVM subclass hidden despite a trezor_coin', () {
      final others = evmCoinSubClasses.difference({CoinSubClass.grc20});
      expect(others, isNotEmpty);
      for (final subClass in others) {
        final config = gleecConfig(trezorCoin: 'Ethereum')
          ..['coin'] = 'EVM-${subClass.name}'
          ..['type'] = subClass.name;
        final asset = Asset.fromJson(config, knownIds: const {});
        expect(asset.protocol.subClass, subClass);
        expect(include(asset), isFalse, reason: '${subClass.name} on Trezor');
      }
    });
  });
}
