import 'package:komodo_coins/komodo_coins.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/activation_manager.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/activation_config/activation_config_service.dart';
import 'package:komodo_defi_sdk/src/assets/activated_assets_cache.dart';
import 'package:komodo_defi_sdk/src/assets/asset_history_storage.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/balances/balance_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../helpers/runtime_auth_fixture.dart';
import 'solana_fixtures.dart';

class _Auth extends Mock
    with RuntimeAuthFixture
    implements KomodoDefiLocalAuth {}

class _Client extends Mock implements ApiClient {}

class _History extends Mock implements AssetHistoryStorage {}

class _Lookup extends Mock implements IAssetLookup {}

class _Balances extends Mock implements IBalanceManager {}

class _Config extends Mock implements ActivationConfigService {}

class _Coins extends Mock implements KomodoAssetsUpdateManager {}

class _Cache extends Mock implements ActivatedAssetsCache {}

void main() {
  final sol = solanaAsset();
  final token2022 = solanaToken(sol, token2022: true);

  for (final asset in [sol, token2022]) {
    test(
      'already-active ${asset.id.id} cannot bypass its engine gate',
      () async {
        final auth = _Auth();
        when(
          () => auth.authStateChanges,
        ).thenAnswer((_) => const Stream<KdfUser?>.empty());
        when(() => auth.currentUser).thenAnswer(
          (_) async => const KdfUser(
            walletId: WalletId(
              name: 'fixture',
              pubkeyHash: 'public',
              authOptions: AuthOptions(
                derivationMethod: DerivationMethod.iguana,
              ),
            ),
            isBip39Seed: false,
          ),
        );
        final cache = _Cache();
        when(
          () => cache.getActivatedAssetIds(
            forceRefresh: any(named: 'forceRefresh'),
          ),
        ).thenAnswer((_) async => {sol.id, token2022.id});
        final client = _Client();
        final manager = ActivationManager(
          client,
          auth,
          _History(),
          _Lookup(),
          _Balances(),
          _Config(),
          _Coins(),
          cache,
          solanaCapabilities: SolanaCapabilities(enabled: asset == token2022),
        );
        final coordinator = SharedActivationCoordinator(manager, auth);
        addTearDown(manager.dispose);
        addTearDown(coordinator.dispose);
        await expectLater(
          coordinator.activateAsset(asset),
          throwsUnsupportedError,
        );
        verifyZeroInteractions(client);
        verifyZeroInteractions(cache);
      },
    );
  }
}
