import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/activation/shared_activation_coordinator.dart';
import 'package:komodo_defi_sdk/src/assets/asset_history_storage.dart';
import 'package:komodo_defi_sdk/src/assets/asset_lookup.dart';
import 'package:komodo_defi_sdk/src/gasless/gasless_capability_registry.dart';
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

class _ImmediateStrategy extends TransactionHistoryStrategy {
  _ImmediateStrategy(this.response);

  final MyTxHistoryResponse response;

  @override
  Set<Type> get supportedPaginationModes => const {PagePagination};

  @override
  Future<MyTxHistoryResponse> fetchTransactionHistory(
    ApiClient client,
    Asset asset,
    TransactionPagination pagination,
  ) async => response;

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

Asset _gaslessAsset({required bool nile}) {
  final platformId = nile ? 'TRXT' : 'TRX';
  final tokenId = nile ? 'TESTUSDT-TRC20' : 'USDT-TRC20';
  final contract = nile
      ? 'TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf'
      : 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
  final parent = Asset.fromJson({
    'coin': platformId,
    'type': 'TRX',
    'name': platformId,
    'fname': platformId,
    'wallet_only': true,
    'mm2': 1,
    'decimals': 6,
    'protocol': {
      'type': 'TRX',
      'protocol_data': {'network': nile ? 'Nile' : 'Mainnet'},
    },
    'nodes': <Map<String, dynamic>>[],
  }, knownIds: const {});
  return Asset.fromJson(
    {
      'coin': tokenId,
      'type': 'TRC-20',
      'name': tokenId,
      'fname': tokenId,
      'wallet_only': true,
      'mm2': 1,
      'decimals': 6,
      'protocol': {
        'type': 'TRC20',
        'protocol_data': {'platform': platformId, 'contract_address': contract},
      },
      'contract_address': contract,
      'parent_coin': platformId,
      'nodes': <Map<String, dynamic>>[],
    },
    knownIds: {parent.id},
  );
}

PendingGaslessTransfer _pendingFor(Asset asset) {
  final protocol = asset.protocol as Trc20Protocol;
  return PendingGaslessTransfer(
    traceId: 'trace',
    requestId: '123e4567-e89b-42d3-a456-426614174000',
    assetId: asset.id.id,
    network: 'network',
    sourceAddress: 'TSource',
    custodyAddress: 'TCustody',
    destinationAddress: 'TDestination',
    requestedAmount: Decimal.parse('5'),
    signedMaxFee: Decimal.parse('2'),
    authorizationDeadline: 1999999999,
    authorizationFingerprint: 'fingerprint',
    balanceChanges: BalanceChanges(
      netChange: Decimal.parse('-5'),
      receivedByMe: Decimal.zero,
      spentByMe: Decimal.parse('5'),
      totalAmount: Decimal.parse('5'),
    ),
    fee: FeeInfo.tronGasless(
      coin: asset.id.id,
      feeMethod: 'gasless',
      providerName: 'gasfree',
      gasfreeAddress: 'TCustody',
      transferFee: Decimal.one,
      totalTokenFee: Decimal.one,
    ),
    acceptedAt: DateTime.utc(2026, 7, 12),
    updatedAt: DateTime.utc(2026, 7, 12),
    state: GaslessTransferState.confirming,
    verificationMode: GaslessVerificationMode.legacyOnChain,
    provider: 'TProvider',
    tokenContract: protocol.config['contract_address'] as String,
  );
}

MyTxHistoryResponse _gaslessHistory(Asset asset) => MyTxHistoryResponse(
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
      txHash: 'legacy-hash',
      from: const ['TCustody'],
      to: const ['TDestination'],
      myBalanceChange: '-5',
      blockHeight: 99,
      confirmations: 1,
      timestamp: 1,
      feeDetails: null,
      coin: asset.id.id,
      internalId: 'legacy-hash',
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

  for (final nile in [false, true]) {
    test('legacy GasFree finality refuses aggregate '
        '${nile ? 'Nile' : 'mainnet'} history', () async {
      final client = _MockApiClient();
      final auth = _MockAuth();
      final assetProvider = _MockAssetProvider();
      final activation = _MockActivationCoordinator();
      final pubkeys = _MockPubkeyManager();
      final streaming = _MockEventStreamingManager();
      final assetHistory = _MockAssetHistoryStorage();
      final storage = _RecordingStorage();
      final authChanges = StreamController<KdfUser?>.broadcast(sync: true);
      final asset = _gaslessAsset(nile: nile);
      final pending = _pendingFor(asset);

      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
      when(() => auth.currentUser).thenAnswer((_) async => walletA);
      when(() => assetProvider.fromId(asset.id)).thenReturn(asset);
      when(
        () => assetHistory.getWalletAssets(walletA.walletId),
      ).thenAnswer((_) async => {asset.id.id});
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
        gaslessCapabilities: GaslessCapabilityRegistry(
          configuredAssetIds: {asset.id.id},
        ),
        transactionHistoryStrategies: [
          _ImmediateStrategy(_gaslessHistory(asset)),
        ],
      );
      addTearDown(() async {
        await manager.dispose();
        await authChanges.close();
      });

      final result = await manager.verifyGaslessTransferOnChain(
        asset,
        pending,
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );

      expect(result, GaslessOnChainVerification.pending);
    });
  }
}
