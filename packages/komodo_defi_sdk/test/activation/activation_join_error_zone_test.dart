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

import '../helpers/runtime_auth_fixture.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockAuth extends Mock
    with RuntimeAuthFixture
    implements KomodoDefiLocalAuth {}

class _MockAssetHistory extends Mock implements AssetHistoryStorage {}

class _MockAssetLookup extends Mock implements IAssetLookup {}

class _MockBalanceManager extends Mock implements IBalanceManager {}

class _MockConfigService extends Mock implements ActivationConfigService {}

class _MockAssetsUpdateManager extends Mock
    implements KomodoAssetsUpdateManager {}

class _MockActivatedAssetsCache extends Mock implements ActivatedAssetsCache {}

class _MockActivationManager extends Mock implements ActivationManager {}

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

const _user = KdfUser(
  walletId: WalletId(
    name: 'wallet',
    pubkeyHash: 'wallet-hash',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
  ),
  isBip39Seed: true,
);

/// Both activation registries hand a *single* shared future to every caller
/// that joins an in-flight attempt, and those callers do not all sit in the
/// same error zone. `PubkeyManager._activateForContext` reaches
/// `SharedActivationCoordinator.activateAsset` from inside `retry()`, which
/// runs every attempt in its own `runZonedGuarded`, and work dispatched
/// un-awaited from an attempt keeps running in that zone afterwards.
///
/// Dart refuses to deliver a future's *error* across an error-zone boundary:
/// rather than completing the cross-zone listener, `_propagateToListeners`
/// reports the error as uncaught in the zone that created the future and
/// abandons that listener's future forever. So a failed activation used to
/// leave its joiner hanging - the coordinator's 3/8-minute deadline is the
/// only thing that ever released the chain, and the pubkey path has no
/// deadline at all.
///
/// A `catchError` side listener does not help: it is a separate listener in
/// the *creating* zone, so it suppresses nothing for the cross-zone joiner and
/// the uncaught report still happens.
void main() {
  late Asset asset;
  late _MockAuth auth;

  setUpAll(() {
    final fallbackAsset = Asset.fromJson(_trxConfig(), knownIds: const {});
    registerFallbackValue(fallbackAsset);
    registerFallbackValue(fallbackAsset.id);
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(_user.walletId);
  });

  setUp(() {
    asset = Asset.fromJson(_trxConfig(), knownIds: const {});
    auth = _MockAuth();
    when(() => auth.currentUser).thenAnswer((_) async => _user);
    when(
      () => auth.authStateChanges,
    ).thenAnswer((_) => const Stream<KdfUser?>.empty());
  });

  /// Runs [call] in its own error zone, recording the outcome it observes and
  /// anything the zone is asked to handle as uncaught.
  ///
  /// Models one `retry()` attempt: each gets a fresh `runZonedGuarded`.
  void callFrom(
    Future<void> Function() call,
    Completer<Object?> outcome,
    List<Object> zoneErrors,
  ) {
    runZonedGuarded(() async {
      try {
        await call();
        outcome.complete('completed');
      } catch (e) {
        outcome.complete(e);
      }
    }, (error, _) => zoneErrors.add(error));
  }

  Future<Object?> expectSettled(
    Completer<Object?> outcome, {
    required String reason,
  }) => outcome.future.timeout(
    const Duration(seconds: 5),
    onTimeout: () => throw StateError(reason),
  );

  test(
    'a failed activation reaches a joiner that waits from another error zone',
    () async {
      // SharedActivationCoordinator._pendingActivations.
      final manager = _MockActivationManager();
      when(() => manager.isAssetActive(any())).thenAnswer((_) async => false);
      when(
        () => manager.shouldRefreshTronGaslessActivation(any()),
      ).thenReturn(false);
      final progress = StreamController<ActivationProgress>();
      addTearDown(progress.close);
      when(
        () => manager.activateAsset(any()),
      ).thenAnswer((_) => progress.stream);

      final coordinator = SharedActivationCoordinator(manager, auth);

      final starterZoneErrors = <Object>[];
      final joinerZoneErrors = <Object>[];
      final starterOutcome = Completer<Object?>();
      final joinerOutcome = Completer<Object?>();

      callFrom(
        () => coordinator.activateAsset(asset),
        starterOutcome,
        starterZoneErrors,
      );
      // Let the first call register its pending entry, so the second one takes
      // the join branch rather than starting an activation of its own.
      await pumpEventQueue();
      callFrom(
        () => coordinator.activateAsset(asset),
        joinerOutcome,
        joinerZoneErrors,
      );
      await pumpEventQueue();

      // Fails every pending activation, exactly as a wallet switch does through
      // `_resetState`.
      await coordinator.dispose();

      expect(
        await expectSettled(
          starterOutcome,
          reason: 'the caller that started the activation never completed',
        ),
        isNotNull,
        reason: 'the caller that started the activation must see the failure',
      );
      expect(
        await expectSettled(
          joinerOutcome,
          reason:
              'the joining caller never completed: its error was dropped at '
              'the error-zone boundary',
        ),
        isNotNull,
        reason: 'the joining caller must see the same failure',
      );
      expect(starterZoneErrors, isEmpty);
      expect(joinerZoneErrors, isEmpty);
    },
  );

  test(
    'an abandoned activation reaches a joiner in another error zone',
    () async {
      // ActivationManager._activationCompleters.
      final client = _MockApiClient();
      final history = _MockAssetHistory();
      final lookup = _MockAssetLookup();
      final balances = _MockBalanceManager();
      final config = _MockConfigService();
      final updates = _MockAssetsUpdateManager();
      final cache = _MockActivatedAssetsCache();

      final activationStarted = Completer<void>();
      final activationResponse = Completer<Map<String, dynamic>>();
      when(() => lookup.fromId(asset.id)).thenReturn(asset);
      when(
        () => cache.getActivatedAssetIds(
          forceRefresh: any(named: 'forceRefresh'),
        ),
      ).thenAnswer((_) async => <AssetId>{});
      when(cache.getActivatedAssetIds).thenAnswer((_) async => <AssetId>{});
      when(
        () => history.addAssetToWallet(any(), any()),
      ).thenAnswer((_) async {});
      when(() => balances.precacheBalance(any())).thenAnswer((_) async {});
      when(() => client.executeRpc(any())).thenAnswer((_) {
        if (!activationStarted.isCompleted) activationStarted.complete();
        return activationResponse.future;
      });

      final manager = ActivationManager(
        client,
        auth,
        history,
        lookup,
        balances,
        config,
        updates,
        cache,
      );
      addTearDown(() async {
        // Release the still-suspended starter rather than failing it, so a
        // teardown error cannot be mistaken for the behaviour under test.
        if (!activationResponse.isCompleted) {
          activationResponse.complete({
            'mmrpc': '2.0',
            'result': {
              'current_block': 1,
              'wallet_balance': {
                'wallet_type': 'iguana',
                'accounts': <Map<String, dynamic>>[],
              },
              'nfts_infos': <String, dynamic>{},
            },
          });
        }
        await manager.dispose();
      });

      final starterZoneErrors = <Object>[];
      final joinerZoneErrors = <Object>[];
      final starterOutcome = Completer<Object?>();
      final joinerOutcome = Completer<Object?>();

      callFrom(
        () => manager.activateAsset(asset).drain<void>(),
        starterOutcome,
        starterZoneErrors,
      );
      // The RPC is in flight, so the attempt is registered and the next caller
      // joins it instead of starting a second one.
      await activationStarted.future;
      callFrom(
        () => manager.activateAsset(asset).drain<void>(),
        joinerOutcome,
        joinerZoneErrors,
      );
      await pumpEventQueue();

      // The coordinator's deadline calls this when it gives up on a wedged
      // attempt; it fails the shared completer rather than dropping it.
      await manager.abandonActivation(asset.id, 'wedged');

      expect(
        await expectSettled(
          joinerOutcome,
          reason:
              'the joining caller never completed: its error was dropped at '
              'the error-zone boundary',
        ),
        isNotNull,
        reason: 'the joining caller must observe the abandoned activation',
      );
      expect(joinerZoneErrors, isEmpty);
      expect(starterZoneErrors, isEmpty);
    },
  );
}
