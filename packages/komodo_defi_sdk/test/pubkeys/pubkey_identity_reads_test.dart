import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkeys_storage.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../helpers/counting_session_auth.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockActivationCoordinator extends Mock
    implements SharedActivationCoordinator {}

/// Keeps Hive out of a plain `package:test` run.
class _EmptyPubkeysStorage implements PubkeysStorage {
  @override
  Future<void> purgeWallet(WalletId walletId) async {}

  @override
  Future<Map<String, Map<String, dynamic>>> listForWallet(
    WalletId walletId,
  ) async => const {};

  @override
  Future<void> savePubkeys(
    WalletId walletId,
    String assetTicker,
    AssetPubkeys pubkeys, {
    Set<String> everFundedAddresses = const {},
  }) async {}
}

const _user = KdfUser(
  walletId: WalletId(
    name: 'wallet-a',
    pubkeyHash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
  ),
  isBip39Seed: false,
);

Asset _atom() => Asset(
  id: AssetId(
    id: 'ATOM',
    name: 'Cosmos',
    symbol: AssetSymbol(assetConfigId: 'ATOM'),
    chainId: AssetChainId(chainId: 118, decimalsValue: 6),
    derivationPath: null,
    subClass: CoinSubClass.tendermint,
  ),
  protocol: TendermintProtocol.fromJson({
    'type': 'Tendermint',
    'rpc_urls': [
      {'url': 'http://localhost:26657'},
    ],
  }),
  isWalletOnly: false,
  signMessagePrefix: null,
);

/// Polling pubkeys must not re-verify the wallet identity.
///
/// The watcher refreshes each asset every 30 seconds, and each refresh used to
/// read `currentUser` at about ten checkpoints: twenty identity RPCs per asset
/// per tick, which is what kept `get_wallet_names` and `get_public_key_hash`
/// at about eight a second on an idle wallet. The session token revokes on
/// every sign-in, sign-out and KDF restart, so the ticks need neither.
void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(_atom().id);
  });

  test('watcher ticks refresh pubkeys without identity reads', () {
    final client = _MockApiClient();
    final activation = _MockActivationCoordinator();
    final auth = CountingSessionAuth(_user);
    addTearDown(auth.authChanges.close);
    final asset = _atom();
    var balanceReads = 0;

    when(
      () => activation.isAssetActive(asset.id),
    ).thenAnswer((_) async => true);
    when(
      () => activation.activateAsset(asset),
    ).thenAnswer((_) async => ActivationResult.success(asset.id));
    when(() => activation.wasFreshlyActivated(any())).thenReturn(false);
    when(() => client.executeRpc(any())).thenAnswer((invocation) async {
      final request =
          invocation.positionalArguments.single as Map<String, dynamic>;
      if (request['method'] != 'my_balance') {
        throw StateError('Unexpected RPC method: ${request['method']}');
      }
      balanceReads++;
      return <String, dynamic>{
        'address': 'cosmos1walleta',
        'balance': '1',
        'unspendable_balance': '0',
        'coin': asset.id.id,
      };
    });

    fakeAsync((async) {
      final manager = PubkeyManager(
        client,
        auth,
        activation,
        storage: _EmptyPubkeysStorage(),
      );
      final subscription = manager.watchPubkeys(asset).listen((_) {});
      async.flushMicrotasks();
      final readsAfterFirstFetch = auth.identityReads;
      final balanceReadsAfterFirstFetch = balanceReads;

      for (var tick = 0; tick < 10; tick++) {
        async
          ..elapse(const Duration(seconds: 30))
          ..flushMicrotasks();
      }

      expect(
        balanceReads - balanceReadsAfterFirstFetch,
        10,
        reason: 'every tick must still refresh the pubkeys',
      );
      expect(
        auth.identityReads,
        readsAfterFirstFetch,
        reason: 'this grew by about ten reads per tick before the fix',
      );
      expect(
        readsAfterFirstFetch,
        lessThanOrEqualTo(2),
        reason: 'one read opens the session, one serves the strategy',
      );

      unawaited(subscription.cancel());
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });

  test('a revoked session rejects a refresh before the stream says so', () {
    final client = _MockApiClient();
    final activation = _MockActivationCoordinator();
    final auth = HeldSessionStreamAuth(_user);
    addTearDown(auth.authChanges.close);
    addTearDown(auth.heldSessionEvents.close);
    final asset = _atom();
    var fetchStarted = false;

    when(
      () => activation.isAssetActive(asset.id),
    ).thenAnswer((_) async => true);
    when(
      () => activation.activateAsset(asset),
    ).thenAnswer((_) async => ActivationResult.success(asset.id));
    when(() => activation.wasFreshlyActivated(any())).thenReturn(false);

    fakeAsync((async) {
      // Created inside the fake zone, or its completion would be scheduled on
      // the real microtask queue and never flushed below.
      final response = Completer<Map<String, dynamic>>();
      when(() => client.executeRpc(any())).thenAnswer((_) {
        fetchStarted = true;
        return response.future;
      });
      final manager = PubkeyManager(
        client,
        auth,
        activation,
        storage: _EmptyPubkeysStorage(),
      );
      Object? failure;
      manager
          .refreshPubkeys(asset)
          .then(
            (_) {},
            onError: (Object e) {
              failure = e;
            },
          );
      async
        ..elapse(const Duration(seconds: 1))
        ..flushMicrotasks();
      expect(fetchStarted, isTrue);
      final readsBeforeSwitch = auth.identityReads;

      // The service revokes the session synchronously when the wallet changes;
      // the manager has not heard yet, so only its session check can reject.
      auth.runtimeSessions.invalidate();
      response.complete({
        'address': 'cosmos1walleta',
        'balance': '1',
        'unspendable_balance': '0',
        'coin': asset.id.id,
      });
      async
        ..elapse(const Duration(seconds: 1))
        ..flushMicrotasks();

      expect(failure, isA<WalletChangedDisconnectException>());
      expect(auth.identityReads, readsBeforeSwitch);

      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });
}
