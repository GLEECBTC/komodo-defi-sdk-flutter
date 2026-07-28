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

const _enriched = KdfUser(
  walletId: WalletId(
    name: 'my-wallet',
    pubkeyHash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
  ),
  isBip39Seed: false,
  metadata: {'isImported': true},
);

/// The *same* wallet as [_enriched], observed while `get_public_key_hash` is
/// unavailable: `_ensureAuthenticatedWalletIdentity` deliberately strips the
/// hash so wallet-scoped secrets stay locked until the identity is verified.
const _degraded = KdfUser(
  walletId: WalletId(
    name: 'my-wallet',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
  ),
  isBip39Seed: false,
  metadata: {'isImported': true},
);

/// A genuinely different wallet.
const _other = KdfUser(
  walletId: WalletId(
    name: 'other-wallet',
    pubkeyHash: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
  ),
  isBip39Seed: false,
  metadata: {'isImported': true},
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

/// A transient `get_public_key_hash` failure makes the auth service emit the
/// same wallet without its `pubkeyHash`. `isSameStableWallet` rejects that
/// enriched -> name-only transition by design, which used to send
/// `BalanceManager` down its wallet-changed path: bump the generation, clear
/// the balance cache, cancel every watcher and error-then-close every per-asset
/// controller. Nothing re-creates those, so balances stopped for a wallet that
/// never changed - and the identity RPC is most likely to fail exactly when KDF
/// is saturated by a login's activation fan-out.
void main() {
  late _MockAuth auth;
  late _MockActivationCoordinator activation;
  late _MockPubkeyManager pubkeys;
  late _MockAssetLookup assetLookup;
  late _MockEventStreamingManager eventStreaming;
  late _MockAssetHistoryStorage assetHistory;
  late StreamController<KdfUser?> authChanges;
  late Asset asset;
  late KdfUser? currentUser;

  setUp(() {
    auth = _MockAuth();
    activation = _MockActivationCoordinator();
    pubkeys = _MockPubkeyManager();
    assetLookup = _MockAssetLookup();
    eventStreaming = _MockEventStreamingManager();
    assetHistory = _MockAssetHistoryStorage();
    authChanges = StreamController<KdfUser?>.broadcast();
    asset = _asset();
    currentUser = _enriched;

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
      () => assetHistory.getWalletAssets(any()),
    ).thenAnswer((_) async => {asset.id.id});
    when(
      () => pubkeys.getPubkeys(asset),
    ).thenAnswer((_) async => _pubkeys(asset, '5'));
    when(
      () => pubkeys.watchPubkeys(asset),
    ).thenAnswer((_) => const Stream.empty());
  });

  BalanceManager build() {
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
    return manager;
  }

  setUpAll(() {
    registerFallbackValue(_enriched.walletId);
  });

  test(
    'a degraded identity for the same wallet does not reset state',
    () async {
      final manager = build();

      expect((await manager.getBalance(asset.id)).total, Decimal.fromInt(5));
      expect(
        manager.lastKnownForWallet(asset.id, _enriched.walletId)?.total,
        Decimal.fromInt(5),
      );

      // The identity RPC blips: same wallet, hash stripped.
      currentUser = _degraded;
      authChanges.add(_degraded);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Cache survives, and the manager still answers under the enriched
      // identity it already held.
      expect(
        manager.lastKnownForWallet(asset.id, _enriched.walletId)?.total,
        Decimal.fromInt(5),
        reason: 'a degraded identity is not a wallet change',
      );
    },
  );

  test('a genuinely different wallet still resets state', () async {
    final manager = build();

    expect((await manager.getBalance(asset.id)).total, Decimal.fromInt(5));

    currentUser = _other;
    authChanges.add(_other);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      manager.lastKnownForWallet(asset.id, _enriched.walletId),
      isNull,
      reason: 'wallet A cache must not survive a switch to wallet B',
    );
  });

  test('a sign-out still resets state', () async {
    final manager = build();

    expect((await manager.getBalance(asset.id)).total, Decimal.fromInt(5));

    currentUser = null;
    authChanges.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(manager.lastKnownForWallet(asset.id, _enriched.walletId), isNull);
  });
}
