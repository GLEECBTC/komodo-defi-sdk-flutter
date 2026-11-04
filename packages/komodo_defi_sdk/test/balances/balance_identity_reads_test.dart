import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:fake_async/fake_async.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_history_storage.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/balances/balance_manager.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/streaming/event_streaming_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../helpers/counting_session_auth.dart';

class _MockActivationCoordinator extends Mock
    implements SharedActivationCoordinator {}

class _MockPubkeyManager extends Mock implements PubkeyManager {}

class _MockAssetLookup extends Mock implements IAssetLookup {}

class _MockEventStreamingManager extends Mock
    implements EventStreamingManager {}

class _MockAssetHistoryStorage extends Mock implements AssetHistoryStorage {}

const _user = KdfUser(
  walletId: WalletId(
    name: 'wallet-a',
    pubkeyHash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
  ),
  isBip39Seed: false,
);

/// An EVM platform coin: it streams balances, so its watcher also arms the
/// 30-second stale guard that re-fetches the balance.
Asset _gleec() => Asset.fromJson(const {
  'coin': 'GLEEC',
  'type': 'GRC-20',
  'name': 'Gleec',
  'fname': 'Gleec',
  'mm2': 1,
  'chain_id': 11169,
  'decimals': 18,
  'required_confirmations': 3,
  'derivation_path': "m/44'/60'",
  'protocol': {
    'type': 'ETH',
    'protocol_data': {'chain_id': 11169},
  },
  'nodes': [
    {'url': 'https://evm-rpc.gleec.com', 'ws_url': 'wss://evm-ws.gleec.com'},
  ],
  'swap_contract_address': '0x51d9EfFc20F6965bc8DFD37E797ac52a72fcdb9D',
  'fallback_swap_contract': '0x51d9EfFc20F6965bc8DFD37E797ac52a72fcdb9D',
}, knownIds: const {});

AssetPubkeys _pubkeys(Asset asset) => AssetPubkeys(
  assetId: asset.id,
  keys: [
    PubkeyInfo(
      address: '0xabc',
      derivationPath: null,
      chain: null,
      balance: BalanceInfo(
        total: Decimal.one,
        spendable: Decimal.one,
        unspendable: Decimal.zero,
      ),
      coinTicker: asset.id.id,
    ),
  ],
  availableAddressesCount: 1,
  syncStatus: SyncStatusEnum.success,
);

/// Balance polling must not re-verify the wallet identity.
///
/// Each stale-guard tick captured the wallet context, re-checked it after the
/// fetch and again before emitting - three `currentUser` reads, six identity
/// RPCs, per watched asset every 30 seconds.
void main() {
  setUpAll(() {
    final asset = _gleec();
    registerFallbackValue(asset);
    registerFallbackValue(asset.id);
    registerFallbackValue(_user.walletId);
  });

  test('stale-guard ticks refresh the balance without identity reads', () {
    final asset = _gleec();
    final auth = CountingSessionAuth(_user);
    addTearDown(auth.authChanges.close);
    final activation = _MockActivationCoordinator();
    final pubkeys = _MockPubkeyManager();
    final assetLookup = _MockAssetLookup();
    final assetHistory = _MockAssetHistoryStorage();
    final streaming = _MockEventStreamingManager();
    var refreshes = 0;

    when(() => assetLookup.fromId(asset.id)).thenReturn(asset);
    when(
      () => activation.isAssetActive(asset.id),
    ).thenAnswer((_) async => true);
    when(
      () => activation.activateAsset(asset),
    ).thenAnswer((_) async => ActivationResult.success(asset.id));
    when(
      () => assetHistory.getWalletAssets(_user.walletId),
    ).thenAnswer((_) async => {asset.id.id});
    when(
      () => pubkeys.getPubkeys(asset),
    ).thenAnswer((_) async => _pubkeys(asset));
    when(() => pubkeys.refreshPubkeys(asset)).thenAnswer((_) async {
      refreshes++;
      return _pubkeys(asset);
    });
    when(
      () => streaming.subscribeToBalance(
        coin: any(named: 'coin'),
        streamerCoin: any(named: 'streamerCoin'),
      ),
    ).thenAnswer(
      (_) async =>
          StreamController<BalanceEvent>.broadcast().stream.listen((_) {}),
    );

    fakeAsync((async) {
      final manager = BalanceManager(
        assetLookup: assetLookup,
        auth: auth,
        pubkeyManager: pubkeys,
        activationCoordinator: activation,
        eventStreamingManager: streaming,
        assetHistoryStorage: assetHistory,
      );
      final subscription = manager.watchBalance(asset.id).listen((_) {});
      async.flushMicrotasks();
      final readsAfterStart = auth.identityReads;
      final refreshesAfterStart = refreshes;

      for (var tick = 0; tick < 10; tick++) {
        async
          ..elapse(const Duration(seconds: 30))
          ..flushMicrotasks();
      }

      expect(
        refreshes - refreshesAfterStart,
        10,
        reason: 'every tick must still re-fetch the balance',
      );
      expect(
        auth.identityReads,
        readsAfterStart,
        reason: 'this grew by three reads per tick before the fix',
      );
      expect(
        readsAfterStart,
        lessThanOrEqualTo(2),
        reason: 'one read opens the session, one serves the watcher start',
      );

      unawaited(subscription.cancel());
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });

  test('a revoked session rejects a balance before the stream says so', () {
    final asset = _gleec();
    final auth = HeldSessionStreamAuth(_user);
    addTearDown(auth.authChanges.close);
    addTearDown(auth.heldSessionEvents.close);
    final pubkeys = _MockPubkeyManager();
    final assetLookup = _MockAssetLookup();
    when(() => assetLookup.fromId(asset.id)).thenReturn(asset);

    fakeAsync((async) {
      final refresh = Completer<AssetPubkeys>();
      when(
        () => pubkeys.refreshPubkeys(asset),
      ).thenAnswer((_) => refresh.future);
      final manager = BalanceManager(
        assetLookup: assetLookup,
        auth: auth,
        pubkeyManager: pubkeys,
        activationCoordinator: _MockActivationCoordinator(),
        eventStreamingManager: _MockEventStreamingManager(),
        assetHistoryStorage: _MockAssetHistoryStorage(),
      );
      Object? failure;
      manager
          .getBalance(asset.id, forceRefresh: true)
          .then(
            (_) {},
            onError: (Object error) {
              failure = error;
            },
          );
      async.flushMicrotasks();
      final readsBeforeSwitch = auth.identityReads;

      // The service revokes the session synchronously when the wallet changes;
      // the manager has not heard yet, so only its session check can reject.
      auth.runtimeSessions.invalidate();
      refresh.complete(_pubkeys(asset));
      async.flushMicrotasks();

      expect(failure, isA<WalletChangedDisconnectException>());
      expect(auth.identityReads, readsBeforeSwitch);

      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });
}
