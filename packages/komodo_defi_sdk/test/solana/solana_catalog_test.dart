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

  test(
    'final available and ticker views gate restored custom tokens without deleting storage',
    () async {
      final auth = _Auth();
      when(
        () => auth.authStateChanges,
      ).thenAnswer((_) => const Stream<KdfUser?>.empty());
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
    },
  );
}
