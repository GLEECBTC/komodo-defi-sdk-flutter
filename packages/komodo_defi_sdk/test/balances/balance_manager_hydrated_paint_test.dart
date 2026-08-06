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

class _InMemoryAssetHistoryStorage extends AssetHistoryStorage {
  final Map<String, Set<String>> _walletAssets = {};

  String _key(WalletId walletId) => walletId.pubkeyHash ?? walletId.name;

  @override
  Future<void> storeWalletAssets(
    WalletId walletId,
    Set<String> assetIds,
  ) async {
    _walletAssets[_key(walletId)] = Set<String>.from(assetIds);
  }

  @override
  Future<void> addAssetToWallet(WalletId walletId, String assetId) async {
    final current = await getWalletAssets(walletId);
    current.add(assetId);
    await storeWalletAssets(walletId, current);
  }

  @override
  Future<Set<String>> getWalletAssets(WalletId walletId) async =>
      Set<String>.from(_walletAssets[_key(walletId)] ?? <String>{});

  @override
  Future<bool> hasAmbiguousLegacyHistory(WalletId walletId) async => false;

  @override
  Future<void> clearWalletAssets(WalletId walletId) async {
    _walletAssets.remove(_key(walletId));
  }
}

AssetPubkeys _pubkeysWith(AssetId assetId, int amount) => AssetPubkeys(
  assetId: assetId,
  keys: [
    PubkeyInfo(
      address: 'TTtHydratedExample',
      derivationPath: null,
      chain: null,
      balance: BalanceInfo(
        total: Decimal.fromInt(amount),
        spendable: Decimal.fromInt(amount),
        unspendable: Decimal.zero,
      ),
      coinTicker: assetId.id,
    ),
  ],
  availableAddressesCount: 1,
  syncStatus: SyncStatusEnum.success,
);

void main() {
  late _MockAuth auth;
  late _MockActivationCoordinator activation;
  late _MockPubkeyManager pubkeyManager;
  late _MockAssetLookup assetLookup;
  late _MockEventStreamingManager eventStreamingManager;
  late StreamController<KdfUser?> authChanges;
  late BalanceManager manager;
  late AssetId assetId;
  late Asset asset;

  setUpAll(() {
    registerFallbackValue(
      Asset(
        id: AssetId(
          id: 'FALLBACK',
          name: 'Fallback',
          symbol: AssetSymbol(assetConfigId: 'FALLBACK'),
          chainId: AssetChainId(chainId: 1, decimalsValue: 8),
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
      ),
    );
  });

  setUp(() {
    auth = _MockAuth();
    activation = _MockActivationCoordinator();
    pubkeyManager = _MockPubkeyManager();
    assetLookup = _MockAssetLookup();
    eventStreamingManager = _MockEventStreamingManager();
    authChanges = StreamController<KdfUser?>.broadcast();

    const walletId = WalletId(
      name: 'hydrated-wallet',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
    );

    when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
    when(() => auth.currentUser).thenAnswer(
      (_) async => const KdfUser(walletId: walletId, isBip39Seed: false),
    );

    assetId = AssetId(
      id: 'ATOM',
      name: 'Cosmos',
      symbol: AssetSymbol(assetConfigId: 'ATOM'),
      chainId: AssetChainId(chainId: 118, decimalsValue: 6),
      derivationPath: null,
      subClass: CoinSubClass.tendermint,
    );
    asset = Asset(
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

    when(() => assetLookup.fromId(assetId)).thenReturn(asset);
    when(
      () => eventStreamingManager.subscribeToBalance(coin: assetId.id),
    ).thenThrow(StateError('streaming should not be used in this test'));
    when(
      () => pubkeyManager.watchPubkeys(asset),
    ).thenAnswer((_) => const Stream<AssetPubkeys>.empty());

    manager = BalanceManager(
      assetLookup: assetLookup,
      auth: auth,
      pubkeyManager: pubkeyManager,
      activationCoordinator: activation,
      eventStreamingManager: eventStreamingManager,
      assetHistoryStorage: _InMemoryAssetHistoryStorage(),
    );
  });

  tearDown(() async {
    await manager.dispose();
    await authChanges.close();
  });

  test(
    'persisted balance paints while activation is still in flight',
    () async {
      // Activation never resolves: without the hydrated paint this subscriber
      // would sit on a placeholder indefinitely.
      final stuckActivation = Completer<ActivationResult>();
      when(
        () => activation.isAssetActive(assetId),
      ).thenAnswer((_) async => false);
      when(
        () => activation.activateAsset(any()),
      ).thenAnswer((_) => stuckActivation.future);

      when(
        () => pubkeyManager.hydratedPubkeys(asset),
      ).thenAnswer((_) async => _pubkeysWith(assetId, 7));
      when(
        () => pubkeyManager.getPubkeys(asset),
      ).thenAnswer((_) => Completer<AssetPubkeys>().future);

      final first = await manager
          .watchBalance(assetId)
          .first
          .timeout(const Duration(seconds: 5));

      expect(first.spendable, Decimal.fromInt(7));
      expect(
        stuckActivation.isCompleted,
        isFalse,
        reason: 'the hydrated paint must not wait on activation',
      );
      // It also becomes the last-known value, which is what the overview total
      // and the wallet-list sort read.
      expect(manager.lastKnown(assetId)?.spendable, Decimal.fromInt(7));
    },
  );

  test('a hydration failure never stops the real watcher', () async {
    when(() => activation.isAssetActive(assetId)).thenAnswer((_) async => true);
    when(
      () => activation.activateAsset(any()),
    ).thenAnswer((_) async => ActivationResult.success(assetId));

    // The opportunistic read blows up; the watcher must still deliver.
    when(
      () => pubkeyManager.hydratedPubkeys(asset),
    ).thenThrow(StateError('storage unavailable'));
    when(
      () => pubkeyManager.getPubkeys(asset),
    ).thenAnswer((_) async => _pubkeysWith(assetId, 3));

    // `firstWhere`, not `first`: with no stored asset history this wallet still
    // qualifies for the pre-existing new-wallet zero-balance shortcut, so the
    // synthetic zero legitimately arrives first. What matters here is that the
    // real fetch still lands afterwards.
    final fetched = await manager
        .watchBalance(assetId)
        .firstWhere((balance) => balance.spendable > Decimal.zero)
        .timeout(const Duration(seconds: 5));

    expect(fetched.spendable, Decimal.fromInt(3));
  });
}
