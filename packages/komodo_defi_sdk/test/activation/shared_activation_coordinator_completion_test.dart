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

class _MockApiClient extends Mock implements ApiClient {}

class _MockAuth extends Mock implements KomodoDefiLocalAuth {}

class _MockAssetHistory extends Mock implements AssetHistoryStorage {}

class _MockAssetLookup extends Mock implements IAssetLookup {}

class _MockBalanceManager extends Mock implements IBalanceManager {}

class _MockConfigService extends Mock implements ActivationConfigService {}

class _MockAssetsUpdateManager extends Mock
    implements KomodoAssetsUpdateManager {}

class _MockActivatedAssetsCache extends Mock implements ActivatedAssetsCache {}

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

void main() {
  test(
    'coordinator observes activation side effects exactly once before success',
    () async {
      final client = _MockApiClient();
      final auth = _MockAuth();
      final assetHistory = _MockAssetHistory();
      final assetLookup = _MockAssetLookup();
      final balanceManager = _MockBalanceManager();
      final configService = _MockConfigService();
      final assetsUpdateManager = _MockAssetsUpdateManager();
      final cache = _MockActivatedAssetsCache();
      final asset = Asset.fromJson(_trxConfig(), knownIds: const {});
      const user = KdfUser(
        walletId: WalletId(
          name: 'wallet',
          pubkeyHash: 'wallet-pubkey',
          authOptions: AuthOptions(derivationMethod: DerivationMethod.hdWallet),
        ),
        isBip39Seed: true,
      );

      registerFallbackValue(<String, dynamic>{});
      registerFallbackValue(asset);
      registerFallbackValue(user.walletId);

      when(() => auth.currentUser).thenAnswer((_) async => user);
      when(
        () => auth.authStateChanges,
      ).thenAnswer((_) => const Stream<KdfUser?>.empty());
      when(() => assetLookup.fromId(asset.id)).thenReturn(asset);
      var forceRefreshCount = 0;
      when(cache.getActivatedAssetIds).thenAnswer((_) async => {});
      when(() => cache.getActivatedAssetIds(forceRefresh: true)).thenAnswer((
        _,
      ) async {
        forceRefreshCount++;
        return {asset.id};
      });
      when(cache.invalidate).thenReturn(null);
      when(
        () => assetHistory.addAssetToWallet(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => balanceManager.precacheBalance(any()),
      ).thenAnswer((_) async {});
      when(() => client.executeRpc(any())).thenAnswer(
        (_) async => {
          'mmrpc': '2.0',
          'result': {
            'current_block': 1,
            'wallet_balance': {
              'wallet_type': 'iguana',
              'accounts': <Map<String, dynamic>>[],
            },
            'nfts_infos': <String, dynamic>{},
          },
        },
      );

      final manager = ActivationManager(
        client,
        auth,
        assetHistory,
        assetLookup,
        balanceManager,
        configService,
        assetsUpdateManager,
        cache,
      );
      final coordinator = SharedActivationCoordinator(manager, auth);
      addTearDown(coordinator.dispose);
      addTearDown(manager.dispose);

      final result = await coordinator.activateAsset(asset);

      expect(result.isSuccess, isTrue);
      expect(forceRefreshCount, 1);
      verify(
        () => assetHistory.addAssetToWallet(user.walletId, asset.id.id),
      ).called(1);
      verify(() => balanceManager.precacheBalance(asset)).called(1);
      verify(cache.invalidate).called(1);
    },
  );
}
