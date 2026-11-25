import 'dart:async';

import 'package:fake_async/fake_async.dart';
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

/// A UTXO coin with no Electrum servers, like CLC: it can never activate.
Asset _clc() => Asset.fromJson(const {
  'coin': 'CLC',
  'type': 'UTXO',
  'name': 'Collider Coin',
  'fname': 'Collider Coin',
  'mm2': 1,
  'chain_id': 141,
  'decimals': 8,
  'is_testnet': false,
  'required_confirmations': 1,
  'derivation_path': "m/44'/141'",
  'protocol': {'type': 'UTXO'},
  'electrum': <Map<String, dynamic>>[],
}, knownIds: const {});

void main() {
  setUpAll(() {
    final asset = _clc();
    registerFallbackValue(asset);
    registerFallbackValue(asset.id);
    registerFallbackValue(_user.walletId);
  });

  test('recovery for an asset that cannot activate asks once per tick', () {
    final asset = _clc();
    final auth = CountingSessionAuth(_user);
    addTearDown(auth.authChanges.close);
    final activation = _MockActivationCoordinator();
    final assetLookup = _MockAssetLookup();
    final assetHistory = _MockAssetHistoryStorage();
    var activationRequests = 0;

    when(() => assetLookup.fromId(asset.id)).thenReturn(asset);
    when(() => activation.isAssetActive(asset.id))
        .thenAnswer((_) async => false);
    when(() => activation.activateAsset(asset)).thenAnswer((_) async {
      activationRequests++;
      return ActivationResult.failure(asset.id, 'servers list is empty');
    });
    when(() => assetHistory.getWalletAssets(_user.walletId))
        .thenAnswer((_) async => {asset.id.id});

    fakeAsync((async) {
      final manager = BalanceManager(
        assetLookup: assetLookup,
        auth: auth,
        pubkeyManager: _MockPubkeyManager(),
        activationCoordinator: activation,
        eventStreamingManager: _MockEventStreamingManager(),
        assetHistoryStorage: assetHistory,
      );
      final subscription = manager
          .watchBalance(asset.id)
          .listen((_) {}, onError: (Object _) {});
      async.flushMicrotasks();
      final requestsAfterStart = activationRequests;

      for (var tick = 0; tick < 10; tick++) {
        async
          ..elapse(const Duration(seconds: 30))
          ..flushMicrotasks();
      }

      // A stale guard used to run beside the polling on the same interval,
      // so this was 20.
      expect(activationRequests - requestsAfterStart, 10);
      expect(
        requestsAfterStart,
        2,
        reason: 'the watcher start, then one immediate recovery attempt',
      );

      unawaited(subscription.cancel());
      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
  });
}
