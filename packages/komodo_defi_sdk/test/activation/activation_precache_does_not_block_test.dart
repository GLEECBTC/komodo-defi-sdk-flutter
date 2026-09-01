import 'dart:async';

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

/// Activation must not wait on its own balance pre-cache.
///
/// `_handleActivationComplete` runs before the terminal `ActivationProgress` is
/// yielded, and it used to `await _balanceManager.precacheBalance(asset)`.
/// `precacheBalance` awaits `PubkeyManager.getPubkeys`, which on a first-ever
/// fetch re-enters `SharedActivationCoordinator.activateAsset` for the very
/// asset still being activated. The coordinator joins its own pending completer
/// - a completer that is only completed once this handler returns - so the
/// activation waits on itself, with no timeout anywhere on the chain. Every
/// caller blocked on that activation (the wallet's login fan-out, the balance
/// watcher's `_ensureAssetActivated`) hangs with it and the coin sits on
/// `activating` for the rest of the session.
///
/// A `precacheBalance` that never completes stands in for that cycle here.
void main() {
  test(
    'terminal progress is reached even if precacheBalance never completes',
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
      when(cache.getActivatedAssetIds).thenAnswer((_) async => {});
      when(
        () => cache.getActivatedAssetIds(forceRefresh: true),
      ).thenAnswer((_) async => {asset.id});
      when(cache.invalidate).thenReturn(null);
      when(
        () => assetHistory.addAssetToWallet(any(), any()),
      ).thenAnswer((_) async {});

      // The deadlock, modelled: the pre-cache can only finish after the
      // activation it is blocking has finished.
      final neverCompletes = Completer<void>();
      addTearDown(() {
        if (!neverCompletes.isCompleted) neverCompletes.complete();
      });
      when(
        () => balanceManager.precacheBalance(any()),
      ).thenAnswer((_) => neverCompletes.future);

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

      final result = await coordinator
          .activateAsset(asset)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => fail(
              'activation blocked on its own balance pre-cache - the terminal '
              'ActivationProgress was never reached',
            ),
          );

      expect(result.isSuccess, isTrue);
      // Still requested, just no longer gating the terminal event.
      verify(() => balanceManager.precacheBalance(asset)).called(1);
    },
  );
}
