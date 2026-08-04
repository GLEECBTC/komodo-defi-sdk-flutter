import 'dart:async';

import 'package:decimal/decimal.dart';
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

/// Never returns, standing in for an activation that is still polling KDF.
class _NeverStrategy extends TransactionHistoryStrategy {
  @override
  Set<Type> get supportedPaginationModes => const {PagePagination};

  @override
  Future<MyTxHistoryResponse> fetchTransactionHistory(
    ApiClient client,
    Asset asset,
    TransactionPagination pagination,
  ) => Completer<MyTxHistoryResponse>().future;

  @override
  bool supportsAsset(Asset asset) => true;
}

class _SeededStorage implements TransactionStorage {
  _SeededStorage(this.seeded);

  final List<Transaction> seeded;

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
    transactions: seeded,
    total: seeded.length,
    currentPage: pageNumber ?? 1,
    totalPages: 1,
  );

  @override
  Future<void> storeTransaction(
    Transaction transaction,
    WalletId walletId,
  ) async {}

  @override
  Future<void> storeTransactions(
    List<Transaction> transactions,
    WalletId walletId,
  ) async {}
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

Transaction _cachedTx(AssetId assetId) => Transaction(
  id: 'internal-cached',
  internalId: 'internal-cached',
  assetId: assetId,
  txHash: 'hash-cached',
  from: const ['cosmos1source'],
  to: const ['cosmos1destination'],
  timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
  confirmations: 1,
  blockHeight: 99,
  balanceChanges: BalanceChanges(
    netChange: Decimal.parse('-1'),
    receivedByMe: Decimal.zero,
    spentByMe: Decimal.parse('1'),
    totalAmount: Decimal.parse('1'),
  ),
);

void main() {
  const wallet = KdfUser(
    walletId: WalletId(
      name: 'wallet-a',
      pubkeyHash: 'wallet-a-hash',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
    ),
    isBip39Seed: false,
    metadata: {'isImported': true},
  );

  test(
    'cached transactions are yielded before activation completes',
    () async {
      final client = _MockApiClient();
      final auth = _MockAuth();
      final assetProvider = _MockAssetProvider();
      final activation = _MockActivationCoordinator();
      final pubkeys = _MockPubkeyManager();
      final streaming = _MockEventStreamingManager();
      final assetHistory = _MockAssetHistoryStorage();
      final asset = _asset();
      final authChanges = StreamController<KdfUser?>.broadcast(sync: true);

      // Activation never resolves: this is the stalled-coin case that used to
      // hold the coin page on a spinner despite cached rows being in memory.
      final stuckActivation = Completer<ActivationResult>();

      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
      when(() => auth.currentUser).thenAnswer((_) async => wallet);
      when(() => assetProvider.fromId(asset.id)).thenReturn(asset);
      when(
        () => activation.activateAsset(asset),
      ).thenAnswer((_) => stuckActivation.future);

      final manager = TransactionHistoryManager(
        client,
        auth,
        assetProvider,
        activation,
        pubkeyManager: pubkeys,
        eventStreamingManager: streaming,
        storage: _SeededStorage([_cachedTx(asset.id)]),
        assetHistoryStorage: assetHistory,
        transactionHistoryStrategies: [_NeverStrategy()],
      );
      addTearDown(() async {
        await authChanges.close();
        await manager.dispose();
      });

      final firstBatch = await manager
          .getTransactionsStreamed(asset)
          .first
          .timeout(const Duration(seconds: 5));

      expect(firstBatch, hasLength(1));
      expect(firstBatch.single.internalId, 'internal-cached');
      expect(
        stuckActivation.isCompleted,
        isFalse,
        reason: 'cached rows must not wait on activation',
      );
    },
  );
}
