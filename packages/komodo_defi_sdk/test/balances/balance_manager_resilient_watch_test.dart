import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_history_storage.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/balances/balance_manager.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/streaming/event_streaming_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAuth extends Mock implements KomodoDefiLocalAuth {}

class _MockActivationCoordinator extends Mock
    implements SharedActivationCoordinator {}

class _MockPubkeyManager extends Mock implements PubkeyManager {}

class _MockAssetLookup extends Mock implements IAssetLookup {}

class _MockEventStreamingManager extends Mock
    implements EventStreamingManager {}

class _MockAssetHistoryStorage extends Mock implements AssetHistoryStorage {}

const _wallet = KdfUser(
  walletId: WalletId(
    name: 'wallet-a',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
  ),
  isBip39Seed: false,
);

Asset _asset() {
  final assetId = AssetId(
    id: 'ATOM',
    name: 'Cosmos',
    symbol: AssetSymbol(assetConfigId: 'ATOM'),
    chainId: AssetChainId(chainId: 118, decimalsValue: 6),
    derivationPath: null,
    subClass: CoinSubClass.tendermint,
  );
  return Asset(
    id: assetId,
    protocol: TendermintProtocol.fromJson({
      'type': 'Tendermint',
      'rpc_urls': [
        {'url': 'http://localhost:26657'},
      ],
    }),
    isWalletOnly: false,
    signMessagePrefix: null,
  );
}

AssetPubkeys _pubkeys(Asset asset, String total) => AssetPubkeys(
  assetId: asset.id,
  keys: [
    PubkeyInfo(
      address: 'cosmos1abc',
      derivationPath: null,
      chain: null,
      balance: BalanceInfo(
        total: Decimal.parse(total),
        spendable: Decimal.parse(total),
        unspendable: Decimal.zero,
      ),
      coinTicker: asset.id.id,
    ),
  ],
  availableAddressesCount: 1,
  syncStatus: SyncStatusEnum.success,
);

/// Polls until [predicate] holds or the budget runs out, so a test never
/// depends on an exact number of event-loop turns.
Future<void> _waitUntil(
  bool Function() predicate, {
  Duration budget = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(budget);
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(_asset());
    registerFallbackValue(_wallet.walletId);
  });

  test(
    'recovers when the preamble runs before the user is observable',
    () async {
      final auth = _MockAuth();
      final activation = _MockActivationCoordinator();
      final pubkeys = _MockPubkeyManager();
      final assetLookup = _MockAssetLookup();
      final assetHistory = _MockAssetHistoryStorage();
      final authChanges = StreamController<KdfUser?>.broadcast();
      final asset = _asset();

      // The failure this reproduces: `watchBalance` is called while the SDK's
      // own auth read still returns null, which is ordinary on the login path
      // because wallet rows render before the read resolves. As an `async*`
      // generator this threw `AuthException.notSignedIn` out of the preamble
      // and ended the caller's stream for good.
      KdfUser? currentUser;

      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
      when(() => auth.currentUser).thenAnswer((_) async => currentUser);
      when(() => assetLookup.fromId(asset.id)).thenReturn(asset);
      when(
        () => activation.isAssetActive(asset.id),
      ).thenAnswer((_) async => true);
      when(
        () => activation.activateAsset(asset),
      ).thenAnswer((_) async => ActivationResult.success(asset.id));
      when(
        () => assetHistory.getWalletAssets(_wallet.walletId),
      ).thenAnswer((_) async => {asset.id.id});
      when(
        () => pubkeys.getPubkeys(asset),
      ).thenAnswer((_) async => _pubkeys(asset, '7'));
      when(
        () => pubkeys.watchPubkeys(asset),
      ).thenAnswer((_) => const Stream.empty());

      final manager = BalanceManager(
        assetLookup: assetLookup,
        auth: auth,
        pubkeyManager: pubkeys,
        activationCoordinator: activation,
        eventStreamingManager: _MockEventStreamingManager(),
        assetHistoryStorage: assetHistory,
      );

      final balances = <BalanceInfo>[];
      final errors = <Object>[];
      var isDone = false;
      final subscription = manager
          .watchBalance(asset.id)
          .listen(
            balances.add,
            onError: errors.add,
            onDone: () => isDone = true,
          );
      addTearDown(() async {
        await subscription.cancel();
        await manager.dispose();
        await authChanges.close();
      });

      await _waitUntil(() => errors.isNotEmpty);
      expect(
        errors.whereType<AuthException>(),
        isNotEmpty,
        reason: 'the transient failure is still reported',
      );
      expect(isDone, isFalse, reason: 'but it must not end the stream');

      // The user becomes observable; the same stream picks it up.
      currentUser = _wallet;

      await _waitUntil(() => balances.isNotEmpty);
      expect(balances.first.total, Decimal.fromInt(7));
    },
  );

  test('is re-listenable after the last listener leaves', () async {
    final auth = _MockAuth();
    final activation = _MockActivationCoordinator();
    final pubkeys = _MockPubkeyManager();
    final assetLookup = _MockAssetLookup();
    final assetHistory = _MockAssetHistoryStorage();
    final authChanges = StreamController<KdfUser?>.broadcast();
    final asset = _asset();

    when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
    when(() => auth.currentUser).thenAnswer((_) async => _wallet);
    when(() => assetLookup.fromId(asset.id)).thenReturn(asset);
    when(
      () => activation.isAssetActive(asset.id),
    ).thenAnswer((_) async => true);
    when(
      () => activation.activateAsset(asset),
    ).thenAnswer((_) async => ActivationResult.success(asset.id));
    when(
      () => assetHistory.getWalletAssets(_wallet.walletId),
    ).thenAnswer((_) async => {asset.id.id});
    when(
      () => pubkeys.getPubkeys(asset),
    ).thenAnswer((_) async => _pubkeys(asset, '3'));
    when(
      () => pubkeys.watchPubkeys(asset),
    ).thenAnswer((_) => const Stream.empty());

    final manager = BalanceManager(
      assetLookup: assetLookup,
      auth: auth,
      pubkeyManager: pubkeys,
      activationCoordinator: activation,
      eventStreamingManager: _MockEventStreamingManager(),
      assetHistoryStorage: assetHistory,
    );
    addTearDown(() async {
      await manager.dispose();
      await authChanges.close();
    });

    // One stream held for the caller's lifetime, listened to more than once -
    // a `StreamBuilder` unmounting and remounting behind a visibility toggle.
    // As an `async*` generator the second listen threw
    // `Bad state: Stream has already been listened to`.
    final stream = manager.watchBalance(asset.id);

    final first = <BalanceInfo>[];
    final firstSubscription = stream.listen(first.add);
    await _waitUntil(() => first.isNotEmpty);
    expect(first.first.total, Decimal.fromInt(3));
    await firstSubscription.cancel();

    final second = <BalanceInfo>[];
    final secondSubscription = stream.listen(second.add);
    addTearDown(secondSubscription.cancel);

    // The replay of the last known balance means a remount shows a value
    // immediately rather than blanking until the next round trip.
    await _waitUntil(() => second.isNotEmpty);
    expect(second.first.total, Decimal.fromInt(3));
  });

  test(
    'a re-attach does not hand the watcher start a fresh retry budget',
    () async {
      final auth = _MockAuth();
      final activation = _MockActivationCoordinator();
      final pubkeys = _MockPubkeyManager();
      final assetLookup = _MockAssetLookup();
      final assetHistory = _MockAssetHistoryStorage();
      final authChanges = StreamController<KdfUser?>.broadcast();
      final asset = _asset();

      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
      when(() => auth.currentUser).thenAnswer((_) async => _wallet);
      when(
        () => activation.isAssetActive(asset.id),
      ).thenAnswer((_) async => true);
      when(
        () => assetHistory.getWalletAssets(_wallet.walletId),
      ).thenAnswer((_) async => {asset.id.id});
      when(
        () => pubkeys.watchPubkeys(asset),
      ).thenAnswer((_) => const Stream.empty());

      // A watcher start that can never succeed. Every attempt reaches the asset
      // lookup, fails it, and errors the asset's controller without registering
      // a watcher.
      var lookups = 0;
      when(() => assetLookup.fromId(asset.id)).thenAnswer((_) {
        lookups++;
        return null;
      });

      final manager = BalanceManager(
        assetLookup: assetLookup,
        auth: auth,
        pubkeyManager: pubkeys,
        activationCoordinator: activation,
        eventStreamingManager: _MockEventStreamingManager(),
        assetHistoryStorage: assetHistory,
        watcherStartRetryDelay: const Duration(milliseconds: 1),
        watcherStartMaxRetryDelay: const Duration(milliseconds: 4),
        maxWatcherStartRetries: 3,
      );

      final errors = <Object>[];
      final subscription = manager
          .watchBalance(asset.id)
          .listen((_) {}, onError: errors.add);
      addTearDown(() async {
        await subscription.cancel();
        await manager.dispose();
        await authChanges.close();
      });

      // 1 initial start + 3 retries, then the start gives up.
      await _waitUntil(() => lookups >= 4);
      expect(lookups, 4);

      // The give-up errors the controller, which makes the subscriber
      // re-attach. Re-attaching drives the asset's controller through another
      // 0 -> 1 listener transition, and `onListen` is what arms a start - so
      // without the give-up latch the count would restart from zero here,
      // forever. Give the backoff far longer than a full budget would need and
      // assert nothing more was attempted.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(
        lookups,
        4,
        reason: 'the watcher start must stay given up until a wallet reset',
      );
      expect(errors, isNotEmpty);
    },
  );

  test('a wallet reset revives a subscriber that stood down', () async {
    final auth = _MockAuth();
    final activation = _MockActivationCoordinator();
    final pubkeys = _MockPubkeyManager();
    final assetLookup = _MockAssetLookup();
    final assetHistory = _MockAssetHistoryStorage();
    final authChanges = StreamController<KdfUser?>.broadcast();
    final asset = _asset();
    var currentUser = _wallet;

    when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
    when(() => auth.currentUser).thenAnswer((_) async => currentUser);
    when(
      () => activation.isAssetActive(asset.id),
    ).thenAnswer((_) async => true);
    when(
      () => activation.activateAsset(asset),
    ).thenAnswer((_) async => ActivationResult.success(asset.id));
    when(
      () => assetHistory.getWalletAssets(any()),
    ).thenAnswer((_) async => {asset.id.id});
    when(
      () => pubkeys.getPubkeys(asset),
    ).thenAnswer((_) async => _pubkeys(asset, '11'));
    when(
      () => pubkeys.watchPubkeys(asset),
    ).thenAnswer((_) => const Stream.empty());

    // Un-startable until the wallet changes.
    var lookupSucceeds = false;
    when(
      () => assetLookup.fromId(asset.id),
    ).thenAnswer((_) => lookupSucceeds ? asset : null);

    final manager = BalanceManager(
      assetLookup: assetLookup,
      auth: auth,
      pubkeyManager: pubkeys,
      activationCoordinator: activation,
      eventStreamingManager: _MockEventStreamingManager(),
      assetHistoryStorage: assetHistory,
      watcherStartRetryDelay: const Duration(milliseconds: 1),
      watcherStartMaxRetryDelay: const Duration(milliseconds: 4),
      maxWatcherStartRetries: 2,
    );

    final balances = <BalanceInfo>[];
    final subscription = manager
        .watchBalance(asset.id)
        .listen(balances.add, onError: (_) {});
    addTearDown(() async {
      await subscription.cancel();
      await manager.dispose();
      await authChanges.close();
    });

    await _waitUntil(() => manager.hasActiveWatcher(asset.id) == false);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(balances, isEmpty);

    // A wallet change clears the give-up latch. The subscriber stood down
    // rather than retrying, so nothing but the reset itself can revive it.
    lookupSucceeds = true;
    currentUser = const KdfUser(
      walletId: WalletId(
        name: 'wallet-b',
        authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
      ),
      isBip39Seed: false,
    );
    authChanges.add(currentUser);

    await _waitUntil(() => balances.isNotEmpty);
    expect(balances.first.total, Decimal.fromInt(11));
  });

  test('completes only when the manager is disposed', () async {
    final auth = _MockAuth();
    final activation = _MockActivationCoordinator();
    final pubkeys = _MockPubkeyManager();
    final assetLookup = _MockAssetLookup();
    final assetHistory = _MockAssetHistoryStorage();
    final authChanges = StreamController<KdfUser?>.broadcast();
    final asset = _asset();

    when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
    when(() => auth.currentUser).thenAnswer((_) async => _wallet);
    when(() => assetLookup.fromId(asset.id)).thenReturn(asset);
    when(
      () => activation.isAssetActive(asset.id),
    ).thenAnswer((_) async => true);
    when(
      () => activation.activateAsset(asset),
    ).thenAnswer((_) async => ActivationResult.success(asset.id));
    when(
      () => assetHistory.getWalletAssets(_wallet.walletId),
    ).thenAnswer((_) async => {asset.id.id});
    when(
      () => pubkeys.getPubkeys(asset),
    ).thenAnswer((_) async => _pubkeys(asset, '2'));
    when(
      () => pubkeys.watchPubkeys(asset),
    ).thenAnswer((_) => const Stream.empty());

    final manager = BalanceManager(
      assetLookup: assetLookup,
      auth: auth,
      pubkeyManager: pubkeys,
      activationCoordinator: activation,
      eventStreamingManager: _MockEventStreamingManager(),
      assetHistoryStorage: assetHistory,
    );
    addTearDown(authChanges.close);

    final balances = <BalanceInfo>[];
    var isDone = false;
    final subscription = manager
        .watchBalance(asset.id)
        .listen(balances.add, onError: (_) {}, onDone: () => isDone = true);
    addTearDown(subscription.cancel);

    await _waitUntil(() => balances.isNotEmpty);
    expect(isDone, isFalse);

    await manager.dispose();

    await _waitUntil(() => isDone);
    expect(isDone, isTrue);
  });
}
