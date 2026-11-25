import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_coins/komodo_coins.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/assets/activated_assets_cache.dart';
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart';
import 'package:komodo_defi_sdk/src/sdk/komodo_defi_sdk_config.dart';
import 'package:komodo_defi_sdk/src/sdk/solana_catalog_policy.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'solana_fixtures.dart';

class _Auth extends Mock implements KomodoDefiLocalAuth {}

class _Coins extends Mock implements KomodoAssetsUpdateManager {}

class _Cache extends Mock implements ActivatedAssetsCache {}

void main() {
  final sol = solanaAsset();
  final classic = solanaToken(sol);
  final token2022 = solanaToken(sol, token2022: true);
  final unknown = Asset.fromJson(
    {
      ...classic.protocol.config,
      'coin': 'UNKNOWN-TESTSOL',
      'protocol': {
        'type': 'SOLANATOKEN',
        'protocol_data': {
          ...(classic.protocol as SolanaTokenProtocol).protocolData,
          'program_id': 'UnverifiedTokenProgram',
        },
      },
    },
    knownIds: {sol.id},
  );

  setUpAll(() => registerFallbackValue(const NoAssetFilterStrategy()));
  test('catalog gate is transient and Token-2022 opt-in is independent', () {
    final configs = [
      sol,
      classic,
      token2022,
      unknown,
    ].map((asset) => asset.protocol.config).toList();
    final disabled = CoinConfigListTransformer.applyTransformsAndFilter(
      configs,
      transformer: const CoinConfigTransformer(
        additionalTransforms: [SolanaCatalogPolicy(SolanaCapabilities())],
      ),
    );
    expect(disabled, isEmpty);
    final enabled = CoinConfigListTransformer.applyTransformsAndFilter(
      configs,
      transformer: const CoinConfigTransformer(
        additionalTransforms: [
          SolanaCatalogPolicy(SolanaCapabilities(enabled: true)),
        ],
      ),
    );
    expect(enabled.map((c) => c['coin']), [sol.id.id, classic.id.id]);
    expect(configs.every((c) => c['excluded'] != true), isTrue);
    const verified2022 = SolanaCatalogPolicy(
      SolanaCapabilities(enabled: true, token2022Enabled: true),
    );
    expect(verified2022.allows(token2022), isTrue);
    expect(verified2022.allows(unknown), isFalse);
  });

  group('gate follows the protocol an entry resolves to', () {
    const disabled = SolanaCatalogPolicy(SolanaCapabilities());
    const enabled = SolanaCatalogPolicy(SolanaCapabilities(enabled: true));
    const with2022 = SolanaCatalogPolicy(
      SolanaCapabilities(enabled: true, token2022Enabled: true),
    );

    for (final type in ['SOLANA', 'Solana', 'solana', 'SOL', 'sol']) {
      for (final (shape, protocol) in <(String, Map<String, dynamic>?)>[
        ('the same protocol type', {'type': type}),
        ('no protocol', null),
        ('a foreign protocol type', {'type': 'UTXO'}),
      ]) {
        test('platform spelled "$type" with $shape', () {
          final config = {...sol.protocol.config, 'type': type};
          if (protocol == null) {
            config.remove('protocol');
          } else {
            config['protocol'] = protocol;
          }
          // The resolver lists this entry as Solana, so the gate must agree.
          final asset = Asset.fromJson(config);
          expect(asset.protocol, isA<SolanaProtocol>());
          expect(disabled.allowsConfig(config), isFalse);
          expect(disabled.needsTransform(config), isTrue);
          expect(disabled.transform(config)['excluded'], isTrue);
          expect(disabled.allows(asset), isFalse);
          expect(enabled.allowsConfig(config), isTrue);
          expect(enabled.allows(asset), isTrue);
        });
      }
    }

    for (final type in [
      'SOLANATOKEN',
      'SolanaToken',
      'Solana Token',
      'solana_token',
      'SPL',
      'spl',
      'SPL Token',
      'SPL-Token',
    ]) {
      test('token spelled "$type"', () {
        for (final (token, classicProgram) in [
          (classic, true),
          (token2022, false),
        ]) {
          final config = {...token.protocol.config, 'type': type};
          final asset = Asset.fromJson(config, knownIds: {sol.id});
          expect(asset.protocol, isA<SolanaTokenProtocol>());
          expect(disabled.allowsConfig(config), isFalse);
          expect(disabled.allows(asset), isFalse);
          expect(enabled.allowsConfig(config), classicProgram);
          expect(enabled.allows(asset), classicProgram);
          expect(with2022.allowsConfig(config), isTrue);
          expect(with2022.allows(asset), isTrue);
        }
        final unverified = {...unknown.protocol.config, 'type': type};
        expect(with2022.allowsConfig(unverified), isFalse);
      });
    }

    test('a Solana protocol under a foreign top-level type stays gated', () {
      for (final config in [
        {...sol.protocol.config, 'type': 'UTXO'},
        {...classic.protocol.config, 'type': 'ERC-20'},
      ]) {
        expect(disabled.allowsConfig(config), isFalse);
      }
    });

    test('no other catalog protocol is mistaken for Solana', () {
      // Every `type` / `protocol.type` spelling in the bundled coins config.
      const types = [
        'ERC-20', 'BEP-20', 'UTXO', 'Polygon', 'AVX-20', 'Arbitrum', 'KRC-20',
        'Base', 'Smart Chain', 'QRC-20', 'GRC-20', 'Gnosis', 'TENDERMINT',
        'Monad', 'Plasma', 'TENDERMINTTOKEN', 'Mantle', 'HyperEVM', 'Flare',
        'SIA', 'Bittensor', 'TRX', 'TRC-20', 'XDC', 'ZHTLC',
        'RSK Smart Bitcoin', 'Ethereum Classic', 'EWT', 'Moonriver',
        'Moonbeam', 'HRC-20', 'SmartBCH', 'ETH', 'Matic', 'FTM-20', //
      ];
      const protocolTypes = [
        'ERC20', 'UTXO', 'ETH', 'QRC20', 'TENDERMINT', 'TENDERMINTTOKEN',
        'NFT', 'QTUM', 'SIA', 'TRX', 'TRC20', 'ZHTLC', 'BCH', 'SLPTOKEN',
        'LIGHTNING', //
      ];
      for (final type in types) {
        for (final protocolType in protocolTypes) {
          final config = <String, dynamic>{
            'coin': 'OTHER',
            'type': type,
            'protocol': {'type': protocolType},
          };
          expect(
            disabled.allowsConfig(config),
            isTrue,
            reason: '$type / $protocolType',
          );
          expect(disabled.needsTransform(config), isFalse);
        }
      }
      expect(disabled.allowsConfig({'coin': 'UNTYPED'}), isTrue);
    });
  });

  test('final available and ticker views gate restored custom tokens without deleting storage', () async {
    final auth = _Auth();
    when(() => auth.authStateChanges)
        .thenAnswer((_) => const Stream<KdfUser?>.empty());
    final coins = _Coins();
    var snapshot = {
      sol.id: sol,
      classic.id: classic,
      token2022.id: token2022,
      unknown.id: unknown,
    };
    when(() => coins.isInitialized).thenReturn(true);
    when(() => coins.filteredAssets(any())).thenAnswer((_) => snapshot);
    final manager = AssetManager(
      auth,
      const KomodoDefiSdkConfig(
        solanaCapabilities: SolanaCapabilities(enabled: true),
      ),
      () => throw StateError('activation not needed'),
      coins,
      () => _Cache(),
    );
    addTearDown(manager.dispose);
    expect(manager.available.keys, [sol.id, classic.id]);
    expect(manager.findAssetsByConfigId(token2022.id.id), isEmpty);
    expect(manager.childAssetsOf(sol.id), {classic});
    expect(identical(manager.available, manager.available), isTrue);
    expect(snapshot, hasLength(4));
    snapshot = {sol.id: sol, token2022.id: token2022};
    expect(manager.available.keys, [sol.id]);
    expect(manager.findAssetsByConfigId(classic.id.id), isEmpty);
  });
}
