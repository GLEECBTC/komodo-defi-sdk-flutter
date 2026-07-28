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

const _walletA = KdfUser(
  walletId: WalletId(
    name: 'wallet-a',
    pubkeyHash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
  ),
  isBip39Seed: false,
  metadata: {'isImported': true},
);

const _walletB = KdfUser(
  walletId: WalletId(
    name: 'wallet-b',
    pubkeyHash: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
  ),
  isBip39Seed: false,
  metadata: {'isImported': true},
);

const _nameOnlyWallet = KdfUser(
  walletId: WalletId(
    name: 'shared-name',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
  ),
  isBip39Seed: false,
  metadata: {'isImported': true},
);

const _hashAWallet = KdfUser(
  walletId: WalletId(
    name: 'shared-name',
    pubkeyHash: 'hash-a',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
  ),
  isBip39Seed: false,
  metadata: {'isImported': true},
);

const _hashBWallet = KdfUser(
  walletId: WalletId(
    name: 'shared-name',
    pubkeyHash: 'hash-b',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
  ),
  isBip39Seed: false,
  metadata: {'isImported': true},
);

const _upgradedWallet = KdfUser(
  walletId: WalletId(
    name: 'upgraded-wallet',
    pubkeyHash: 'upgraded-wallet-hash',
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
        {'url': 'https://rpc.example.com'},
      ],
    }),
    isWalletOnly: false,
    signMessagePrefix: null,
  );
}

AssetPubkeys _pubkeys(Asset asset, String amount) => AssetPubkeys(
  assetId: asset.id,
  keys: [
    PubkeyInfo(
      address: 'cosmos1$amount',
      derivationPath: null,
      chain: null,
      balance: BalanceInfo(
        total: Decimal.parse(amount),
        spendable: Decimal.parse(amount),
        unspendable: Decimal.zero,
      ),
      coinTicker: asset.id.id,
    ),
  ],
  availableAddressesCount: 0,
  syncStatus: SyncStatusEnum.success,
);

Future<void> _waitForActiveWatcher(
  BalanceManager manager,
  AssetId assetId,
) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (manager.hasActiveWatcher(assetId)) return;
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _waitForNoActiveWatcher(
  BalanceManager manager,
  AssetId assetId,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (!manager.hasActiveWatcher(assetId)) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test(
    'delayed auth event cannot emit wallet A cached balance to wallet B',
    () async {
      final auth = _MockAuth();
      final activation = _MockActivationCoordinator();
      final pubkeys = _MockPubkeyManager();
      final assetLookup = _MockAssetLookup();
      final eventStreaming = _MockEventStreamingManager();
      final assetHistory = _MockAssetHistoryStorage();
      final authChanges = StreamController<KdfUser?>.broadcast();
      KdfUser? currentUser = _walletA;
      final asset = _asset();

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
        () => assetHistory.getWalletAssets(_walletA.walletId),
      ).thenAnswer((_) async => {asset.id.id});
      when(
        () => assetHistory.getWalletAssets(_walletB.walletId),
      ).thenAnswer((_) async => {asset.id.id});
      when(() => pubkeys.getPubkeys(asset)).thenAnswer(
        (_) async => _pubkeys(asset, currentUser == _walletA ? '5' : '9'),
      );
      when(
        () => pubkeys.watchPubkeys(asset),
      ).thenAnswer((_) => const Stream.empty());

      final manager = BalanceManager(
        assetLookup: assetLookup,
        auth: auth,
        pubkeyManager: pubkeys,
        activationCoordinator: activation,
        eventStreamingManager: eventStreaming,
        assetHistoryStorage: assetHistory,
      );
      addTearDown(() async {
        await manager.dispose();
        await authChanges.close();
      });

      expect((await manager.getBalance(asset.id)).total, Decimal.fromInt(5));
      expect(
        manager.lastKnownForWallet(asset.id, _walletA.walletId)?.total,
        Decimal.fromInt(5),
      );

      currentUser = _walletB;
      // Deliberately do not emit authChanges. The async currentUser check must
      // invalidate A before watchBalance considers any cached value.
      expect(manager.lastKnownForWallet(asset.id, _walletB.walletId), isNull);

      final firstForWalletB = await manager.watchBalance(asset.id).first;

      expect(firstForWalletB.total, Decimal.fromInt(9));
      expect(
        manager.lastKnownForWallet(asset.id, _walletB.walletId)?.total,
        Decimal.fromInt(9),
      );
    },
  );

  test(
    'stale controller cannot swallow replacement watcher teardown',
    () async {
      final auth = _MockAuth();
      final activation = _MockActivationCoordinator();
      final pubkeys = _MockPubkeyManager();
      final assetLookup = _MockAssetLookup();
      final eventStreaming = _MockEventStreamingManager();
      final assetHistory = _MockAssetHistoryStorage();
      final authChanges = StreamController<KdfUser?>.broadcast();
      KdfUser? currentUser = _walletA;
      final asset = _asset();

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
        () => assetHistory.getWalletAssets(_walletA.walletId),
      ).thenAnswer((_) async => {asset.id.id});
      when(
        () => assetHistory.getWalletAssets(_walletB.walletId),
      ).thenAnswer((_) async => {asset.id.id});
      when(() => pubkeys.getPubkeys(asset)).thenAnswer(
        (_) async => _pubkeys(asset, currentUser == _walletA ? '5' : '9'),
      );
      when(
        () => pubkeys.watchPubkeys(asset),
      ).thenAnswer((_) => const Stream.empty());

      final manager = BalanceManager(
        assetLookup: assetLookup,
        auth: auth,
        pubkeyManager: pubkeys,
        activationCoordinator: activation,
        eventStreamingManager: eventStreaming,
        assetHistoryStorage: assetHistory,
      );
      final walletAFirst = Completer<BalanceInfo>();
      final walletADisconnecting = Completer<void>();
      final walletADone = Completer<void>();
      late final StreamSubscription<BalanceInfo> walletASubscription;
      walletASubscription = manager
          .watchBalance(asset.id)
          .listen(
            (balance) {
              if (!walletAFirst.isCompleted) walletAFirst.complete(balance);
            },
            onError: (Object error) {
              if (error is WalletChangedDisconnectException &&
                  !walletADisconnecting.isCompleted) {
                // Hold the old controller open while wallet B installs its
                // replacement. Its later onCancel must not tear B down.
                walletASubscription.pause();
                walletADisconnecting.complete();
              }
            },
            onDone: walletADone.complete,
          );
      StreamSubscription<BalanceInfo>? walletBSubscription;
      addTearDown(() async {
        await walletASubscription.cancel();
        await walletBSubscription?.cancel();
        await manager.dispose();
        await authChanges.close();
      });

      expect((await walletAFirst.future).total, Decimal.fromInt(5));
      expect(manager.hasActiveWatcher(asset.id), isTrue);

      currentUser = _walletB;
      authChanges.add(_walletB);
      await walletADisconnecting.future;

      final walletBFirst = Completer<BalanceInfo>();
      walletBSubscription = manager.watchBalance(asset.id).listen((balance) {
        if (!walletBFirst.isCompleted) walletBFirst.complete(balance);
      });
      expect((await walletBFirst.future).total, Decimal.fromInt(9));
      await _waitForActiveWatcher(manager, asset.id);
      expect(manager.hasActiveWatcher(asset.id), isTrue);

      await walletBSubscription.cancel();
      walletBSubscription = null;
      walletASubscription.resume();
      await walletADone.future;
      await _waitForNoActiveWatcher(manager, asset.id);

      expect(manager.hasActiveWatcher(asset.id), isFalse);
      expect(
        manager.lastKnownForWallet(asset.id, _walletB.walletId)?.total,
        Decimal.fromInt(9),
      );
    },
  );

  test(
    'auth enrichment makes a later same-name hash switch clear balance cache',
    () async {
      final auth = _MockAuth();
      final pubkeys = _MockPubkeyManager();
      final assetLookup = _MockAssetLookup();
      final authChanges = StreamController<KdfUser?>.broadcast(sync: true);
      KdfUser? currentUser = _nameOnlyWallet;
      final asset = _asset();

      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
      when(() => auth.currentUser).thenAnswer((_) async => currentUser);
      when(() => assetLookup.fromId(asset.id)).thenReturn(asset);
      when(() => pubkeys.getPubkeys(asset)).thenAnswer(
        (_) async => _pubkeys(
          asset,
          currentUser?.walletId.pubkeyHash == 'hash-b' ? '9' : '5',
        ),
      );

      final manager = BalanceManager(
        assetLookup: assetLookup,
        auth: auth,
        pubkeyManager: pubkeys,
        activationCoordinator: _MockActivationCoordinator(),
        eventStreamingManager: _MockEventStreamingManager(),
        assetHistoryStorage: _MockAssetHistoryStorage(),
      );
      addTearDown(() async {
        await manager.dispose();
        await authChanges.close();
      });

      expect((await manager.getBalance(asset.id)).total, Decimal.fromInt(5));

      currentUser = _hashAWallet;
      authChanges.add(_hashAWallet);
      expect(
        manager.lastKnownForWallet(asset.id, _hashAWallet.walletId)?.total,
        Decimal.fromInt(5),
      );

      currentUser = _hashBWallet;
      authChanges.add(_hashBWallet);
      expect(
        manager.lastKnownForWallet(asset.id, _hashBWallet.walletId),
        isNull,
      );
      expect((await manager.getBalance(asset.id)).total, Decimal.fromInt(9));
    },
  );

  test(
    'ambiguous legacy history disables the new-wallet zero shortcut',
    () async {
      final auth = _MockAuth();
      final activation = _MockActivationCoordinator();
      final pubkeys = _MockPubkeyManager();
      final assetLookup = _MockAssetLookup();
      final eventStreaming = _MockEventStreamingManager();
      final assetHistory = _MockAssetHistoryStorage();
      final authChanges = StreamController<KdfUser?>.broadcast();
      final asset = _asset();

      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
      when(() => auth.currentUser).thenAnswer((_) async => _upgradedWallet);
      when(() => assetLookup.fromId(asset.id)).thenReturn(asset);
      when(
        () => assetHistory.getWalletAssets(_upgradedWallet.walletId),
      ).thenAnswer((_) async => {});
      when(
        () => assetHistory.hasAmbiguousLegacyHistory(_upgradedWallet.walletId),
      ).thenAnswer((_) async => true);
      when(
        () => activation.isAssetActive(asset.id),
      ).thenAnswer((_) async => true);
      when(
        () => pubkeys.getPubkeys(asset),
      ).thenAnswer((_) async => _pubkeys(asset, '5'));
      when(
        () => pubkeys.watchPubkeys(asset),
      ).thenAnswer((_) => const Stream.empty());

      final manager = BalanceManager(
        assetLookup: assetLookup,
        auth: auth,
        pubkeyManager: pubkeys,
        activationCoordinator: activation,
        eventStreamingManager: eventStreaming,
        assetHistoryStorage: assetHistory,
      );
      addTearDown(() async {
        await manager.dispose();
        await authChanges.close();
      });

      final first = await manager.watchBalance(asset.id).first;

      expect(first.total, Decimal.fromInt(5));
    },
  );
}
