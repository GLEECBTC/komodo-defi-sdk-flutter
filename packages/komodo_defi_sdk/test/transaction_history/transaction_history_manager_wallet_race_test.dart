import 'dart:async';

import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_history_storage.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/streaming/event_streaming_manager.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_history_manager.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_storage.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockAuth extends Mock implements KomodoDefiLocalAuth {}

class _MockAssetProvider extends Mock implements IAssetProvider {}

class _MockActivationCoordinator extends Mock
    implements SharedActivationCoordinator {}

class _MockPubkeyManager extends Mock implements PubkeyManager {}

class _MockEventStreamingManager extends Mock
    implements EventStreamingManager {}

class _MockAssetHistoryStorage extends Mock implements AssetHistoryStorage {}

class _BlockingStrategy extends TransactionHistoryStrategy {
  _BlockingStrategy(this.response);

  final Completer<MyTxHistoryResponse> response;

  @override
  Set<Type> get supportedPaginationModes => const {PagePagination};

  @override
  Future<MyTxHistoryResponse> fetchTransactionHistory(
    ApiClient client,
    Asset asset,
    TransactionPagination pagination,
  ) => response.future;

  @override
  bool supportsAsset(Asset asset) => true;
}

class _RecordingStorage implements TransactionStorage {
  final storedWallets = <WalletId>[];

  @override
  Future<void> clearTransactions(AssetId assetId, WalletId walletId) async {}

  @override
  Future<Transaction?> getTransactionById(String internalId) async => null;

  @override
  Future<String?> getLatestTransactionId(
    AssetId assetId,
    WalletId walletId,
  ) async => null;

  @override
  Future<StorageStats> getStats() => throw UnimplementedError();

  @override
  Future<TransactionPage> getTransactions(
    AssetId assetId,
    WalletId walletId, {
    String? fromId,
    int? pageNumber,
    int limit = 10,
  }) async => TransactionPage(
    transactions: const [],
    total: 0,
    currentPage: pageNumber ?? 1,
    totalPages: 0,
  );

  @override
  Future<void> storeTransaction(
    Transaction transaction,
    WalletId walletId,
  ) async {
    storedWallets.add(walletId);
  }

  @override
  Future<void> storeTransactions(
    List<Transaction> transactions,
    WalletId walletId,
  ) async {
    storedWallets.add(walletId);
  }
}

Asset _asset() {
  final id = AssetId(
    id: 'ATOM',
    name: 'Cosmos',
    symbol: AssetSymbol(assetConfigId: 'ATOM'),
    chainId: AssetChainId(chainId: 118, decimalsValue: 6),
    derivationPath: null,
    subClass: CoinSubClass.tendermint,
  );
  return Asset(
    id: id,
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

MyTxHistoryResponse _historyResponse() => MyTxHistoryResponse(
  mmrpc: RpcVersion.v2_0,
  currentBlock: 100,
  fromId: null,
  limit: 50,
  skipped: 0,
  syncStatus: SyncStatusResponse(state: TransactionSyncStatusEnum.finished),
  total: 1,
  totalPages: 1,
  pageNumber: 1,
  pagingOptions: null,
  transactions: [
    TransactionInfo(
      txHash: 'hash-a',
      from: const ['cosmos1source'],
      to: const ['cosmos1destination'],
      myBalanceChange: '-1',
      blockHeight: 99,
      confirmations: 1,
      timestamp: 1,
      feeDetails: null,
      coin: 'ATOM',
      internalId: 'internal-a',
      memo: null,
    ),
  ],
);

void main() {
  const walletA = KdfUser(
    walletId: WalletId(
      name: 'wallet-a',
      pubkeyHash: 'wallet-a-hash',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
    ),
    isBip39Seed: false,
    metadata: {'isImported': true},
  );
  const walletB = KdfUser(
    walletId: WalletId(
      name: 'wallet-b',
      pubkeyHash: 'wallet-b-hash',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
    ),
    isBip39Seed: false,
    metadata: {'isImported': true},
  );
  const nameOnlyWallet = KdfUser(
    walletId: WalletId(
      name: 'shared-name',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
    ),
    isBip39Seed: false,
    metadata: {'isImported': true},
  );
  const hashAWallet = KdfUser(
    walletId: WalletId(
      name: 'shared-name',
      pubkeyHash: 'hash-a',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
    ),
    isBip39Seed: false,
    metadata: {'isImported': true},
  );
  const hashBWallet = KdfUser(
    walletId: WalletId(
      name: 'shared-name',
      pubkeyHash: 'hash-b',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
    ),
    isBip39Seed: false,
    metadata: {'isImported': true},
  );
  const upgradedWallet = KdfUser(
    walletId: WalletId(
      name: 'upgraded-wallet',
      pubkeyHash: 'upgraded-wallet-hash',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
    ),
    isBip39Seed: false,
  );

  test('wallet switch cannot store wallet A history under wallet B', () async {
    final client = _MockApiClient();
    final auth = _MockAuth();
    final assetProvider = _MockAssetProvider();
    final activation = _MockActivationCoordinator();
    final pubkeys = _MockPubkeyManager();
    final streaming = _MockEventStreamingManager();
    final assetHistory = _MockAssetHistoryStorage();
    final storage = _RecordingStorage();
    final authChanges = StreamController<KdfUser?>.broadcast(sync: true);
    final strategyResponse = Completer<MyTxHistoryResponse>();
    KdfUser? currentUser = walletA;
    final asset = _asset();

    when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
    when(() => auth.currentUser).thenAnswer((_) async => currentUser);
    when(() => assetProvider.fromId(asset.id)).thenReturn(asset);
    when(
      () => assetHistory.getWalletAssets(walletA.walletId),
    ).thenAnswer((_) async => {'ATOM'});
    when(
      () => activation.activateAsset(asset),
    ).thenAnswer((_) async => ActivationResult.success(asset.id));

    final manager = TransactionHistoryManager(
      client,
      auth,
      assetProvider,
      activation,
      pubkeyManager: pubkeys,
      eventStreamingManager: streaming,
      storage: storage,
      assetHistoryStorage: assetHistory,
      transactionHistoryStrategies: [_BlockingStrategy(strategyResponse)],
    );
    addTearDown(() async {
      await manager.dispose();
      await authChanges.close();
    });

    final pending = manager.getTransactionHistory(asset);
    await Future<void>.delayed(Duration.zero);
    currentUser = walletB;
    // Deliberately delay the auth-stream event. The stable-wallet check must
    // still reject the stale result by consulting currentUser at commit time.
    strategyResponse.complete(_historyResponse());

    await expectLater(
      pending,
      throwsA(isA<WalletChangedDisconnectException>()),
    );
    expect(storage.storedWallets, isEmpty);
  });

  test(
    'auth enrichment makes a later same-name hash reject stale history',
    () async {
      final client = _MockApiClient();
      final auth = _MockAuth();
      final assetProvider = _MockAssetProvider();
      final activation = _MockActivationCoordinator();
      final pubkeys = _MockPubkeyManager();
      final streaming = _MockEventStreamingManager();
      final assetHistory = _MockAssetHistoryStorage();
      final storage = _RecordingStorage();
      final authChanges = StreamController<KdfUser?>.broadcast(sync: true);
      final strategyResponse = Completer<MyTxHistoryResponse>();
      KdfUser? currentUser = nameOnlyWallet;
      final asset = _asset();

      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
      when(() => auth.currentUser).thenAnswer((_) async => currentUser);
      when(() => assetProvider.fromId(asset.id)).thenReturn(asset);
      when(
        () => assetHistory.getWalletAssets(nameOnlyWallet.walletId),
      ).thenAnswer((_) async => {'ATOM'});
      when(
        () => activation.activateAsset(asset),
      ).thenAnswer((_) async => ActivationResult.success(asset.id));

      final manager = TransactionHistoryManager(
        client,
        auth,
        assetProvider,
        activation,
        pubkeyManager: pubkeys,
        eventStreamingManager: streaming,
        storage: storage,
        assetHistoryStorage: assetHistory,
        transactionHistoryStrategies: [_BlockingStrategy(strategyResponse)],
      );
      addTearDown(() async {
        await manager.dispose();
        await authChanges.close();
      });

      final pending = manager.getTransactionHistory(asset);
      await Future<void>.delayed(Duration.zero);

      currentUser = hashAWallet;
      authChanges.add(hashAWallet);
      currentUser = hashBWallet;
      authChanges.add(hashBWallet);
      strategyResponse.complete(_historyResponse());

      await expectLater(
        pending,
        throwsA(isA<WalletChangedDisconnectException>()),
      );
      expect(storage.storedWallets, isEmpty);
    },
  );

  test(
    'ambiguous legacy history disables the new-wallet empty shortcut',
    () async {
      final client = _MockApiClient();
      final auth = _MockAuth();
      final assetProvider = _MockAssetProvider();
      final activation = _MockActivationCoordinator();
      final pubkeys = _MockPubkeyManager();
      final streaming = _MockEventStreamingManager();
      final assetHistory = _MockAssetHistoryStorage();
      final storage = _RecordingStorage();
      final authChanges = StreamController<KdfUser?>.broadcast();
      final strategyResponse = Completer<MyTxHistoryResponse>()
        ..complete(_historyResponse());
      final asset = _asset();

      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
      when(() => auth.currentUser).thenAnswer((_) async => upgradedWallet);
      when(() => assetProvider.fromId(asset.id)).thenReturn(asset);
      when(
        () => assetHistory.getWalletAssets(upgradedWallet.walletId),
      ).thenAnswer((_) async => {});
      when(
        () => assetHistory.hasAmbiguousLegacyHistory(upgradedWallet.walletId),
      ).thenAnswer((_) async => true);
      when(
        () => activation.activateAsset(asset),
      ).thenAnswer((_) async => ActivationResult.success(asset.id));

      final manager = TransactionHistoryManager(
        client,
        auth,
        assetProvider,
        activation,
        pubkeyManager: pubkeys,
        eventStreamingManager: streaming,
        storage: storage,
        assetHistoryStorage: assetHistory,
        transactionHistoryStrategies: [_BlockingStrategy(strategyResponse)],
      );
      addTearDown(() async {
        await manager.dispose();
        await authChanges.close();
      });

      final page = await manager.getTransactionHistory(asset);

      expect(page.total, 1);
      expect(storage.storedWallets, [upgradedWallet.walletId]);
    },
  );
}
