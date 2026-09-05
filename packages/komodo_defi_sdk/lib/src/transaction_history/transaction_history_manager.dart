import 'dart:async';
import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart'
    show BalanceEvent;
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/_internal_exports.dart';
import 'package:komodo_defi_sdk/src/auth/wallet_operation_context.dart';
import 'package:komodo_defi_sdk/src/gasless/gasless_capability_registry.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/streaming/event_streaming_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Core interface for transaction history manager
abstract interface class _TransactionHistoryManager {
  /// Get transaction history with pagination support
  Future<TransactionPage> getTransactionHistory(
    Asset asset, {
    TransactionPagination? pagination,
  });

  /// Stream of new transactions for an asset
  Stream<Transaction> watchTransactions(Asset asset);

  /// Sync transaction history for an asset
  Future<void> syncTransactionHistory(Asset asset);

  /// Clear transaction history for an asset
  Future<void> clearTransactionHistory(Asset asset);

  /// Similar to [getTransactionHistory] but returns a stream of transactions
  /// with the initial batch from storage and the latest transactions from
  /// the API. The stream will close when the latest transaction is reached.
  Stream<List<Transaction>> getTransactionsStreamed(Asset asset);

  /// High-level merged history stream for UI list consumption.
  ///
  /// This stream handles update reconciliation, pending->confirmed bridging,
  /// and stable ordering internally.
  Stream<List<Transaction>> watchTransactionHistoryMerged(
    Asset asset, {
    Transaction Function(Transaction transaction)? transform,
  });
}

class TransactionHistoryManager implements _TransactionHistoryManager {
  TransactionHistoryManager(
    this._client,
    this._auth,
    this._assetProvider,
    this._activationCoordinator, {
    required PubkeyManager pubkeyManager,
    required EventStreamingManager eventStreamingManager,
    TransactionStorage? storage,
    AssetHistoryStorage? assetHistoryStorage,
    GaslessCapabilityRegistry? gaslessCapabilities,
    List<TransactionHistoryStrategy>? transactionHistoryStrategies,
  }) : _storage = storage ?? TransactionStorage.defaultForPlatform(),
       _pubkeyManager = pubkeyManager,
       _strategyFactory = TransactionHistoryStrategyFactory(
         pubkeyManager,
         _auth,
         strategies: transactionHistoryStrategies,
         includeGaslessCustody: gaslessCapabilities?.canAccessExistingCustody,
       ),
       _eventStreamingManager = eventStreamingManager,
       _gaslessCapabilities = gaslessCapabilities,
       _assetHistoryStorage = assetHistoryStorage ?? AssetHistoryStorage() {
    // Subscribe to auth changes directly in constructor
    _authSubscription = _auth.authStateChanges.listen(_handleAuthStateChanged);
  }

  final ApiClient _client;
  final KomodoDefiLocalAuth _auth;
  final PubkeyManager _pubkeyManager;
  final IAssetProvider _assetProvider;
  final SharedActivationCoordinator _activationCoordinator;
  final TransactionStorage _storage;
  final EventStreamingManager _eventStreamingManager;
  final AssetHistoryStorage _assetHistoryStorage;
  final GaslessCapabilityRegistry? _gaslessCapabilities;

  final _streamControllers = <AssetId, StreamController<Transaction>>{};
  final _txHistorySubscriptions = <AssetId, StreamSubscription<dynamic>>{};
  final _pollingTimers = <AssetId, Timer>{};
  // Periodic confirmations refresh timers while streaming is healthy
  final _confirmationsTimers = <AssetId, Timer>{};
  final _balanceFallbackSubscriptions =
      <AssetId, StreamSubscription<BalanceEvent>>{};
  final _lastBalanceForPolling = <AssetId, BalanceInfo>{};
  final _lastCustodyBalanceForPolling = <AssetId, Decimal>{};
  final _syncInProgress = <(AssetId, int)>{};

  /// Assets this process has successfully activated for the current wallet.
  ///
  /// The activation skip in [getTransactionHistory] used to key off "we have
  /// local history for this asset", on the reasoning that stored rows prove a
  /// prior activation. That reasoning only holds while storage is per-process.
  /// Once history is persisted, a cold start has rows for an asset KDF has not
  /// enabled yet, and the strategy fetch below it would run against an inactive
  /// coin. Tracking activation per session keeps the RPC-spam reduction the
  /// skip was added for without inheriting a cross-session claim.
  final _activatedThisSession = <AssetId>{};
  final _rateLimiter = _RateLimiter(const Duration(milliseconds: 500));

  static const _defaultPollingInterval = Duration(seconds: 30);
  static const _maxPollingRetries = 3;
  static const _maxBatchSize = 50;

  /// Max consecutive strategy responses with no transactions but a non-null
  /// cursor (e.g. TRX history skipping non-TransferContract pages). Prevents
  /// unbounded loops on accounts with only contract traffic.
  static const _maxEmptyPages = 10;

  bool _isDisposed = false;
  StreamSubscription<KdfUser?>? _authSubscription;
  WalletId? _currentWalletId;
  int _walletGeneration = 0;

  final TransactionHistoryStrategyFactory _strategyFactory;

  // Streaming capability helpers based on asset properties
  bool _supportsBalanceStreaming(Asset asset) => asset.supportsBalanceStreaming;

  bool _supportsTxHistoryStreaming(Asset asset) =>
      asset.supportsTxHistoryStreaming;

  void _handleAuthStateChanged(KdfUser? user) {
    if (_isDisposed) return;
    final nextWallet = user?.walletId;
    final currentWalletId = _currentWalletId;
    if (_sameOptionalWallet(currentWalletId, nextWallet)) {
      if (currentWalletId != null && nextWallet != null) {
        _currentWalletId = preferEnrichedWalletIdentity(
          currentWalletId,
          nextWallet,
        );
      }
      return;
    }

    // Identity RPC outages emit a name-only user for the same live session.
    // Preserve its verified cache namespace and subscriptions, just as the
    // capture path does. A sign-out or a different wallet still invalidates
    // every operation below.
    if (currentWalletId != null &&
        nextWallet != null &&
        isDegradedWalletIdentity(currentWalletId, nextWallet)) {
      return;
    }

    // Invalidate first: cancellation is best-effort and queued callbacks may
    // still complete after a wallet switch.
    _walletGeneration++;
    _currentWalletId = nextWallet;
    _lastBalanceForPolling.clear();
    _lastCustodyBalanceForPolling.clear();
    _syncInProgress.clear();
    _activatedThisSession.clear();
    _stopAllStreaming();
  }

  bool _sameOptionalWallet(WalletId? previous, WalletId? current) {
    if (previous == null || current == null) return previous == current;
    return isSameStableWallet(previous, current);
  }

  Future<WalletOperationContext> _captureWalletContext() async {
    final user = await _auth.currentUser;
    if (user == null) throw StateError('User is not logged in');

    final currentWalletId = _currentWalletId;
    late final WalletId operationWalletId;
    if (currentWalletId == null) {
      _currentWalletId = user.walletId;
      operationWalletId = user.walletId;
    } else if (isSameStableWallet(currentWalletId, user.walletId)) {
      operationWalletId = preferEnrichedWalletIdentity(
        currentWalletId,
        user.walletId,
      );
      _currentWalletId = operationWalletId;
    } else if (isDegradedWalletIdentity(currentWalletId, user.walletId)) {
      // Same wallet, identity RPC temporarily unavailable. Keep operating - and
      // keep keying storage - under the enriched identity already held.
      //
      // Without this branch a transient `get_public_key_hash` failure looks
      // like a wallet switch: the generation bumps, streaming stops, and the
      // history that follows is written under a name-only storage prefix. The
      // rows under the enriched prefix are then orphaned and swept, so this is
      // silent loss of persisted history rather than a re-walk.
      // [BalanceManager] and [PubkeyManager] both already have this branch.
      operationWalletId = currentWalletId;
    } else {
      // Do not wait for the auth stream to deliver before isolating the old
      // wallet's subscriptions and in-flight operations.
      _walletGeneration++;
      _currentWalletId = user.walletId;
      operationWalletId = user.walletId;
      _lastBalanceForPolling.clear();
      _lastCustodyBalanceForPolling.clear();
      _syncInProgress.clear();
      _activatedThisSession.clear();
      _stopAllStreaming();
    }

    return WalletOperationContext(
      walletId: operationWalletId,
      generation: _walletGeneration,
    );
  }

  bool _isWalletContextCurrentSync(WalletOperationContext context) {
    final current = _currentWalletId;
    return !_isDisposed &&
        context.generation == _walletGeneration &&
        current != null &&
        isSameStableWallet(context.walletId, current);
  }

  Future<bool> _isWalletContextCurrent(WalletOperationContext context) async {
    if (!_isWalletContextCurrentSync(context)) return false;
    final user = await _auth.currentUser;
    // Continues-session, not same-stable: the fresh read can observe the same
    // wallet degraded to name-only while the identity RPC is down, which the
    // capture path deliberately admits - rejecting it here would fail the
    // operation during the exact blip that branch tolerates.
    return user != null &&
        _isWalletContextCurrentSync(context) &&
        walletIdentityContinuesSession(context.walletId, user.walletId);
  }

  Future<void> _requireWalletContextCurrent(
    WalletOperationContext context,
  ) async {
    if (await _isWalletContextCurrent(context)) return;
    throw const WalletChangedDisconnectException(
      'Wallet changed while fetching transaction history',
    );
  }

  void _stopAllStreaming() {
    if (_isDisposed) return;

    // Cancel all transaction history subscriptions
    for (final sub in _txHistorySubscriptions.values) {
      sub.cancel().ignore();
    }
    _txHistorySubscriptions.clear();

    // Cancel polling timers
    for (final timer in _pollingTimers.values) {
      timer.cancel();
    }
    _pollingTimers.clear();

    // Cancel confirmations refresh timers
    for (final timer in _confirmationsTimers.values) {
      timer.cancel();
    }
    _confirmationsTimers.clear();

    for (final sub in _balanceFallbackSubscriptions.values) {
      sub.cancel().ignore();
    }
    _balanceFallbackSubscriptions.clear();

    // Close controllers in a separate iteration to avoid modification during iteration
    final controllers = _streamControllers.values.toList();
    _streamControllers.clear();
    for (final controller in controllers) {
      controller.close();
    }
  }

  @override
  Future<TransactionPage> getTransactionHistory(
    Asset asset, {
    TransactionPagination? pagination,
  }) async {
    try {
      if (_isDisposed) {
        throw StateError('TransactionHistoryManager has been disposed');
      }
      final walletContext = await _captureWalletContext();

      // Default to first page if no pagination specified
      pagination ??= const PagePagination(
        pageNumber: 1,
        itemsPerPage: _maxBatchSize,
      );

      // Optimization: Check if this is a newly created wallet (not imported)
      final user = await _auth.currentUser;
      if (user != null &&
          isSameStableWallet(walletContext.walletId, user.walletId) &&
          pagination is PagePagination &&
          pagination.pageNumber == 1) {
        final previouslyEnabledAssets = await _assetHistoryStorage
            .getWalletAssets(walletContext.walletId);
        await _requireWalletContextCurrent(walletContext);
        final isFirstTimeEnabling = !previouslyEnabledAssets.contains(
          asset.id.id,
        );

        // Check metadata to determine if this was an imported wallet
        // Only optimize for genuinely new wallets, not imported ones
        final isImported = user.metadata['isImported'] == true;
        var isNewWallet = previouslyEnabledAssets.isEmpty && !isImported;
        if (isNewWallet) {
          final hasAmbiguousLegacyHistory = await _assetHistoryStorage
              .hasAmbiguousLegacyHistory(walletContext.walletId);
          await _requireWalletContextCurrent(walletContext);
          isNewWallet = !hasAmbiguousLegacyHistory;
        }

        // For newly created wallets (not imported) on first-time asset enablement,
        // assume empty transaction history to reduce RPC spam
        if (isFirstTimeEnabling && isNewWallet) {
          // Still need to activate the asset
          await _ensureAssetActivated(asset, walletContext);

          // Mark asset as seen after activation
          await _assetHistoryStorage.addAssetToWallet(
            walletContext.walletId,
            asset.id.id,
          );
          await _requireWalletContextCurrent(walletContext);

          return TransactionPage(
            transactions: const [],
            total: 0,
            currentPage: 1,
            totalPages: 1,
          );
        }
      }

      // First try to get from local storage. A TransactionBasedPagination
      // cursor is not necessarily a stored internalId: a strategy may hand
      // back its own opaque token as `nextPageId` (TronGrid's encoded
      // per-address cursor), which storage rejects as an unknown starting
      // transaction. That rejection means "not ours to serve", never a failed
      // request - the strategy below owns the cursor and consumes it.
      TransactionPage? localPage;
      try {
        localPage = await _storage.getTransactions(
          asset.id,
          walletContext.walletId,
          fromId: pagination is TransactionBasedPagination
              ? pagination.fromId
              : null,
          pageNumber: pagination is PagePagination
              ? pagination.pageNumber
              : null,
          limit: pagination.limit ?? _maxBatchSize,
        );
      } on TransactionStorageException {
        localPage = null;
      }
      await _requireWalletContextCurrent(walletContext);

      // If we have enough local data and it's not a first page request, return it
      if (localPage != null &&
          localPage.transactions.isNotEmpty &&
          (pagination is PagePagination && pagination.pageNumber > 1 ||
              pagination is TransactionBasedPagination)) {
        return localPage;
      }

      // Skip the activation check only when this process already activated the
      // asset. That reduces RPC spam when the coin details page is reopened
      // repeatedly, without assuming that persisted history implies KDF has the
      // coin enabled right now - it does not, on a cold start.
      if (!_activatedThisSession.contains(asset.id)) {
        await _ensureAssetActivated(asset, walletContext);
      }

      // Get appropriate strategy for the asset
      final strategy = _strategyFactory.forAsset(asset);

      // Apply rate limiting
      await _rateLimiter.throttle();

      // Fetch from API using the appropriate strategy
      final response = await strategy.fetchTransactionHistory(
        _client,
        asset,
        pagination,
      );
      await _requireWalletContextCurrent(walletContext);

      // Convert API response to domain model
      final transactions = response.transactions
          .map((tx) => tx.asTransaction(asset.id))
          .toList();

      // Store in local storage efficiently
      await _batchStoreTransactions(transactions, walletContext);

      return TransactionPage(
        transactions: transactions,
        total: response.total,
        nextPageId: response.fromId,
        currentPage: response.pageNumber ?? 1,
        totalPages: response.totalPages,
      );
    } catch (e) {
      if (e is TransactionStorageException ||
          e is WalletChangedDisconnectException) {
        // Propagate storage-specific errors
        rethrow;
      }
      throw Exception('Failed to fetch transaction history: $e');
    }
  }

  @override
  Stream<List<Transaction>> getTransactionsStreamed(Asset asset) async* {
    if (_isDisposed) {
      throw StateError('TransactionHistoryManager has been disposed');
    }

    // Verify asset exists before proceeding
    if (_assetProvider.fromId(asset.id) == null) {
      throw ArgumentError('Asset ${asset.id.name} not found');
    }
    final walletContext = await _captureWalletContext();

    // Cached rows are yielded *before* activation, not after.
    //
    // `_ensureAssetActivated` has no upper bound - it awaits the shared
    // activation coordinator, which polls KDF indefinitely. Reading storage
    // after it meant a coin page re-opened seconds after the last fetch showed
    // a spinner for as long as activation took, despite every row already
    // being in memory. Storage is a local read and cannot block on the network.
    //
    // Activation is still awaited below, before the network walk: local history
    // does not prove the asset is enabled in KDF *right now*, and that stays
    // true once this storage is persisted across sessions.
    final localPage = await _storage.getTransactions(
      asset.id,
      walletContext.walletId,
      limit: _maxBatchSize,
    );
    await _requireWalletContextCurrent(walletContext);

    if (localPage.transactions.isNotEmpty) {
      yield localPage.transactions;
    }

    try {
      await _ensureAssetActivated(asset, walletContext);
    } catch (e) {
      if (e is ActivationFailedException ||
          e is WalletChangedDisconnectException) {
        rethrow;
      } else {
        // Wrap other errors in ActivationFailedException for consistency
        throw ActivationFailedException(
          assetId: asset.id,
          message: e.toString(),
          errorCode: 'TX_HISTORY_ACTIVATION_ERROR',
          originalError: e,
        );
      }
    }
    final strategy = _strategyFactory.forAsset(asset);

    String? fromId;
    var hasMore = true;
    var retryCount = 0;
    const maxRetries = 3;
    var consecutiveEmptyPages = 0;

    while (hasMore && _isWalletContextCurrentSync(walletContext)) {
      try {
        final response = await strategy.fetchTransactionHistory(
          _client,
          asset,
          fromId != null
              ? TransactionBasedPagination(
                  fromId: fromId,
                  itemCount: _maxBatchSize,
                )
              : const PagePagination(
                  pageNumber: 1,
                  itemsPerPage: _maxBatchSize,
                ),
        );
        await _requireWalletContextCurrent(walletContext);

        if (response.transactions.isEmpty) {
          if (response.fromId != null) {
            consecutiveEmptyPages++;
            if (consecutiveEmptyPages > _maxEmptyPages) {
              hasMore = false;
            } else {
              fromId = response.fromId;
            }
          } else {
            hasMore = false;
          }
          continue;
        }

        consecutiveEmptyPages = 0;

        final transactions = response.transactions
            .map((tx) => tx.asTransaction(asset.id))
            .toList();

        await _batchStoreTransactions(transactions, walletContext);
        yield transactions;

        fromId = response.fromId;

        if (fromId == null) {
          hasMore = false;
        }
      } catch (_) {
        if (!_isWalletContextCurrentSync(walletContext)) return;
        retryCount++;
        if (retryCount >= maxRetries) {
          hasMore = false;
        } else {
          await Future<void>.delayed(
            Duration(milliseconds: 500 * (1 << retryCount)),
          );
        }
      }
    }
  }

  @override
  Stream<List<Transaction>> watchTransactionHistoryMerged(
    Asset asset, {
    Transaction Function(Transaction transaction)? transform,
  }) async* {
    final walletContext = await _captureWalletContext();
    final reconciler = TransactionListReconciler();
    var merged = <Transaction>[];
    var emittedInitial = false;

    await for (final batch in getTransactionsStreamed(asset)) {
      if (!_isWalletContextCurrentSync(walletContext)) return;
      final incoming = transform == null
          ? batch
          : batch.map(transform).toList(growable: false);
      merged = reconciler.merge(existing: merged, incoming: incoming);
      emittedInitial = true;
      yield List<Transaction>.unmodifiable(merged);
    }

    if (!emittedInitial) {
      if (!await _isWalletContextCurrent(walletContext)) return;
      yield const <Transaction>[];
    }

    // Historical fetching may finish because its wallet changed. Never
    // attach the retained rows to a live stream from the next wallet.
    if (!await _isWalletContextCurrent(walletContext)) return;
    await for (final transaction in watchTransactions(asset)) {
      if (!_isWalletContextCurrentSync(walletContext)) return;
      final normalized = transform?.call(transaction) ?? transaction;
      merged = reconciler.merge(existing: merged, incoming: [normalized]);
      yield List<Transaction>.unmodifiable(merged);
    }
  }

  @override
  Stream<Transaction> watchTransactions(Asset asset) {
    if (_isDisposed) {
      throw StateError('TransactionHistoryManager has been disposed');
    }

    final controller = _streamControllers.putIfAbsent(
      asset.id,
      () => StreamController<Transaction>.broadcast(
        onListen: () {
          // Start transaction history streaming only once per asset
          if (!_txHistorySubscriptions.containsKey(asset.id)) {
            _startStreaming(asset);
          }
        },
        onCancel: () async {
          final activeController = _streamControllers[asset.id];
          if (activeController == null || !activeController.hasListener) {
            _stopStreaming(asset.id);
            await activeController?.close();
            _streamControllers.remove(asset.id);
          }
        },
      ),
    );

    return controller.stream;
  }

  @override
  Future<void> syncTransactionHistory(Asset asset) async {
    if (_isDisposed) return;
    final walletContext = await _captureWalletContext();
    final syncIdentity = (asset.id, walletContext.generation);
    if (_syncInProgress.contains(syncIdentity)) return;
    _syncInProgress.add(syncIdentity);

    try {
      final strategy = _strategyFactory.forAsset(asset);
      final latestStoredId = await _storage.getLatestTransactionId(
        asset.id,
        walletContext.walletId,
      );
      await _requireWalletContextCurrent(walletContext);
      if (strategy.usesOpaquePaginationCursor && latestStoredId != null) {
        final newTransactions = await _fetchOpaqueCursorTransactionsSince(
          asset,
          strategy: strategy,
          latestStoredId: latestStoredId,
          walletContext: walletContext,
        );
        await _batchStoreTransactions(newTransactions, walletContext);
        return;
      }

      var fromId = latestStoredId;
      var hasMore = true;
      var consecutiveEmptyPages = 0;

      while (hasMore && _isWalletContextCurrentSync(walletContext)) {
        await _rateLimiter.throttle();
        await _requireWalletContextCurrent(walletContext);

        final response = await strategy.fetchTransactionHistory(
          _client,
          asset,
          fromId != null
              ? TransactionBasedPagination(
                  fromId: fromId,
                  itemCount: _maxBatchSize,
                )
              : const PagePagination(
                  pageNumber: 1,
                  itemsPerPage: _maxBatchSize,
                ),
        );
        await _requireWalletContextCurrent(walletContext);

        if (response.transactions.isEmpty) {
          if (response.fromId != null) {
            consecutiveEmptyPages++;
            if (consecutiveEmptyPages > _maxEmptyPages) {
              hasMore = false;
            } else {
              fromId = response.fromId;
            }
          } else {
            hasMore = false;
          }
          continue;
        }

        consecutiveEmptyPages = 0;

        final transactions = response.transactions
            .map((tx) => tx.asTransaction(asset.id))
            .toList();

        await _batchStoreTransactions(transactions, walletContext);
        fromId = response.fromId;

        if (fromId == null) {
          hasMore = false;
        }
      }
    } finally {
      _syncInProgress.remove(syncIdentity);
    }
  }

  Future<List<Transaction>> _fetchOpaqueCursorTransactionsSince(
    Asset asset, {
    required TransactionHistoryStrategy strategy,
    required String latestStoredId,
    required WalletOperationContext walletContext,
  }) async {
    String? fromId;
    var hasMore = true;
    var consecutiveEmptyPages = 0;
    final newTransactions = <Transaction>[];

    while (hasMore && _isWalletContextCurrentSync(walletContext)) {
      final response = await strategy.fetchTransactionHistory(
        _client,
        asset,
        fromId != null
            ? TransactionBasedPagination(
                fromId: fromId,
                itemCount: _maxBatchSize,
              )
            : const PagePagination(pageNumber: 1, itemsPerPage: _maxBatchSize),
      );
      await _requireWalletContextCurrent(walletContext);

      if (response.transactions.isEmpty) {
        if (response.fromId != null) {
          consecutiveEmptyPages++;
          if (consecutiveEmptyPages > _maxEmptyPages) {
            hasMore = false;
          } else {
            fromId = response.fromId;
          }
        } else {
          hasMore = false;
        }
        continue;
      }

      consecutiveEmptyPages = 0;

      var reachedStoredHead = false;
      for (final tx in response.transactions.map(
        (tx) => tx.asTransaction(asset.id),
      )) {
        if (tx.internalId == latestStoredId) {
          reachedStoredHead = true;
          break;
        }
        newTransactions.add(tx);
      }

      if (reachedStoredHead || response.fromId == null) {
        hasMore = false;
      } else {
        fromId = response.fromId;
      }
    }

    return newTransactions;
  }

  @override
  Future<void> clearTransactionHistory(Asset asset) async {
    if (_isDisposed) return;
    final walletContext = await _captureWalletContext();

    await _requireWalletContextCurrent(walletContext);
    await _storage.clearTransactions(asset.id, walletContext.walletId);
    await _requireWalletContextCurrent(walletContext);
    _stopStreaming(asset.id);
    await _streamControllers[asset.id]?.close();
    _streamControllers.remove(asset.id);
  }

  Future<void> _ensureAssetActivated(
    Asset asset,
    WalletOperationContext walletContext,
  ) async {
    final activationResult = await _activationCoordinator.activateAsset(asset);
    if (activationResult.isFailure) {
      throw ActivationFailedException(
        assetId: asset.id,
        message: activationResult.errorMessage ?? 'Unknown activation error',
        errorCode: 'ACTIVATION_FAILED',
        originalError: activationResult.errorMessage,
      );
    }
    await _requireWalletContextCurrent(walletContext);
    _activatedThisSession.add(asset.id);
  }

  Future<void> _batchStoreTransactions(
    List<Transaction> transactions,
    WalletOperationContext walletContext,
  ) async {
    if (transactions.isEmpty) return;

    try {
      // Resolve and validate the wallet before the storage write. Never resolve
      // "current wallet" after the network fetch: that writes wallet A's
      // response under wallet B when a switch happens during the await.
      await _requireWalletContextCurrent(walletContext);
      await _storage.storeTransactions(transactions, walletContext.walletId);
      await _requireWalletContextCurrent(walletContext);
    } on WalletChangedDisconnectException {
      rethrow;
    } catch (e) {
      throw Exception('Failed to store transactions batch: $e');
    }
  }

  Future<void> _startStreaming(Asset asset) async {
    // Ensure we don't duplicate subscriptions
    _stopStreaming(asset.id);
    final WalletOperationContext walletContext;
    try {
      walletContext = await _captureWalletContext();
    } catch (_) {
      return;
    }

    // Ensure asset is activated before subscribing
    try {
      await _ensureAssetActivated(asset, walletContext);
    } catch (e) {
      final controller = _streamControllers[asset.id];
      if (controller != null && !controller.isClosed) {
        if (e is ActivationFailedException) {
          controller.addError(e);
        } else {
          // Wrap other errors in ActivationFailedException for consistency
          controller.addError(
            ActivationFailedException(
              assetId: asset.id,
              message: e.toString(),
              errorCode: 'TX_WATCH_ACTIVATION_ERROR',
              originalError: e,
            ),
          );
        }
      }
      return;
    }

    // Subscribe to transaction history event stream for real-time updates
    try {
      // Gate by KDF capability to avoid unsupported streaming RPCs
      if (!_supportsTxHistoryStreaming(asset)) {
        await _startPolling(asset, walletContext);
        return;
      }
      final txHistoryStreamSubscription = await _eventStreamingManager
          .subscribeToTxHistory(coin: asset.id.id);
      if (!await _isWalletContextCurrent(walletContext)) {
        await txHistoryStreamSubscription.cancel();
        return;
      }

      // Check again to avoid race condition: only store if not already present
      if (_txHistorySubscriptions.containsKey(asset.id)) {
        await txHistoryStreamSubscription.cancel();
        return;
      }

      var hasFallenBack = false;
      Future<void> fallbackToPolling({
        String reason = 'stream stopped',
        Object? error,
        StackTrace? stackTrace,
      }) async {
        if (hasFallenBack || !_isWalletContextCurrentSync(walletContext)) {
          return;
        }
        hasFallenBack = true;

        if (_txHistorySubscriptions[asset.id] == txHistoryStreamSubscription) {
          _txHistorySubscriptions.remove(asset.id);
        }

        try {
          await txHistoryStreamSubscription.cancel();
        } catch (_) {}

        await _startPolling(asset, walletContext);
      }

      _txHistorySubscriptions[asset.id] = txHistoryStreamSubscription
        ..onData((txHistoryEvent) async {
          if (!_isWalletContextCurrentSync(walletContext)) return;

          // Verify the event is for the correct coin
          if (txHistoryEvent.coin != asset.id.id) return;

          // Process new transactions
          final transactions = txHistoryEvent.transactions
              .map((tx) => tx.asTransaction(asset.id))
              .toList();

          if (transactions.isEmpty) return;

          // Store transactions in local storage
          await _batchStoreTransactions(transactions, walletContext);
          if (!_isWalletContextCurrentSync(walletContext)) return;

          // Emit each transaction to listeners
          final controller = _streamControllers[asset.id];
          if (controller != null && !controller.isClosed) {
            for (final tx in transactions) {
              controller.add(tx);
            }
          }
        })
        ..onError((Object error, StackTrace stackTrace) {
          unawaited(
            fallbackToPolling(
              reason: 'stream error',
              error: error,
              stackTrace: stackTrace,
            ),
          );
        })
        ..onDone(() {
          unawaited(fallbackToPolling(reason: 'stream closed'));
        });

      // Keep confirmations fresh even while the stream is healthy
      _startConfirmationsRefresh(asset, walletContext);
    } catch (_) {
      if (_isWalletContextCurrentSync(walletContext)) {
        await _startPolling(asset, walletContext);
      }
    }
  }

  void _stopStreaming(AssetId assetId) {
    _txHistorySubscriptions[assetId]?.cancel();
    _txHistorySubscriptions.remove(assetId);
    _stopPolling(assetId);
    _stopConfirmationsRefresh(assetId);
  }

  bool _isPollingActive(AssetId assetId) =>
      _pollingTimers.containsKey(assetId) ||
      _balanceFallbackSubscriptions.containsKey(assetId);

  bool _updateLastKnownBalance(AssetId assetId, BalanceInfo balance) {
    final previous = _lastBalanceForPolling[assetId];
    _lastBalanceForPolling[assetId] = balance;

    return previous == null ||
        previous.total != balance.total ||
        previous.spendable != balance.spendable ||
        previous.unspendable != balance.unspendable;
  }

  Future<void> _syncHistoryIfBalanceChanged(
    Asset asset, {
    required WalletOperationContext walletContext,
    BalanceInfo? balance,
    bool force = false,
  }) async {
    if (!_isWalletContextCurrentSync(walletContext)) return;
    if (!_isPollingActive(asset.id)) return;

    var shouldSync = force;

    if (balance != null) {
      final hasChanged = _updateLastKnownBalance(asset.id, balance);
      shouldSync = shouldSync || hasChanged;
    }

    if (!shouldSync) return;

    await _pollNewTransactions(asset, walletContext);
  }

  Future<void> _pollBalanceAndSyncHistory(
    Asset asset, {
    required WalletOperationContext walletContext,
    bool force = false,
  }) async {
    if (!_isWalletContextCurrentSync(walletContext)) return;

    try {
      await _ensureAssetActivated(asset, walletContext);
      final response = await _client.rpc.wallet.myBalance(coin: asset.id.id);
      await _requireWalletContextCurrent(walletContext);
      final custodyChanged = await _custodyBalanceChanged(asset, walletContext);
      await _syncHistoryIfBalanceChanged(
        asset,
        balance: response.balance,
        force: force || custodyChanged,
        walletContext: walletContext,
      );
    } catch (_) {
      if (force && _isWalletContextCurrentSync(walletContext)) {
        await _pollNewTransactions(asset, walletContext);
      }
    }
  }

  /// Whether [asset] is a gasless TRC-20 (any pubkey carries a GasFree
  /// custody address). Custody balance changes are invisible to KDF EOA
  /// balance events, so these assets need custody-aware polling.
  Future<bool> _isGaslessTrc20(
    Asset asset,
    WalletOperationContext walletContext,
  ) async {
    if (asset.protocol is! Trc20Protocol) return false;
    final capabilities = _gaslessCapabilities;
    if (capabilities?.canAccessExistingCustody(asset.id) == true) return true;
    try {
      final pubkeys =
          _pubkeyManager.lastKnownForWallet(asset.id, walletContext.walletId) ??
          await _pubkeyManager.getPubkeys(asset);
      if (!await _isWalletContextCurrent(walletContext)) return false;
      return pubkeys.keys.any((key) => (key.gasfreeAddress ?? '').isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  /// Detects GasFree custody balance changes for gasless TRC-20 assets via
  /// the per-coin gasless account status RPC. Returns false for other assets
  /// or when the status call fails (provider unreachable), so history syncing
  /// falls back to EOA balance gating alone.
  ///
  /// Note: [_fetchOpaqueCursorTransactionsSince] stops at the stored head, so
  /// custody transactions older than the head are not backfilled mid-session.
  /// [getTransactionsStreamed] walks the network from page 1 to exhaustion on
  /// every coin-details open, regardless of what storage already holds, so the
  /// gap self-heals there. That is a property of the walk, not of storage being
  /// per-process, and it survives storage being persisted across sessions.
  ///
  /// The new balance is committed before the triggered sync runs (mirroring
  /// [_updateLastKnownBalance] for EOA balances), so a sync whose retries all
  /// fail drops that one trigger; the next custody movement or a coin-details
  /// reopen (page-1 refetch) recovers.
  Future<bool> _custodyBalanceChanged(
    Asset asset,
    WalletOperationContext walletContext,
  ) async {
    if (!await _isGaslessTrc20(asset, walletContext)) return false;
    final capabilities = _gaslessCapabilities;
    if (capabilities == null || !capabilities.canRefreshAccountStatus(asset)) {
      return false;
    }
    final capabilitySession = capabilities.sessionGeneration;
    try {
      final status = await _client.rpc.withdraw.gaslessAccountStatus(
        coin: asset.id.id,
      );
      if (!await _isWalletContextCurrent(walletContext) ||
          capabilities.sessionGeneration != capabilitySession) {
        return false;
      }
      if (!capabilities.refreshAccountStatus(asset, status)) return false;
      final previous = _lastCustodyBalanceForPolling[asset.id];
      _lastCustodyBalanceForPolling[asset.id] = status.onChainBalance;
      return previous == null || previous != status.onChainBalance;
    } catch (error) {
      if (!_isWalletContextCurrentSync(walletContext) ||
          capabilities.sessionGeneration != capabilitySession) {
        return false;
      }
      capabilities.markAccountStatusError(asset.id, error);
      return false;
    }
  }

  Future<void> _pollNewTransactions(
    Asset asset,
    WalletOperationContext walletContext, [
    int retryCount = 0,
  ]) async {
    if (!_isWalletContextCurrentSync(walletContext)) return;

    try {
      await _ensureAssetActivated(asset, walletContext);
      final strategy = _strategyFactory.forAsset(asset);
      final latestId = await _storage.getLatestTransactionId(
        asset.id,
        walletContext.walletId,
      );
      await _requireWalletContextCurrent(walletContext);

      if (!_isPollingActive(asset.id)) return;

      final newTransactions =
          strategy.usesOpaquePaginationCursor && latestId != null
          ? await _fetchOpaqueCursorTransactionsSince(
              asset,
              strategy: strategy,
              latestStoredId: latestId,
              walletContext: walletContext,
            )
          : (await strategy.fetchTransactionHistory(
              _client,
              asset,
              latestId != null
                  ? TransactionBasedPagination(
                      fromId: latestId,
                      itemCount: _maxBatchSize,
                    )
                  : const PagePagination(
                      pageNumber: 1,
                      itemsPerPage: _maxBatchSize,
                    ),
            )).transactions.map((tx) => tx.asTransaction(asset.id)).toList();
      await _requireWalletContextCurrent(walletContext);

      if (newTransactions.isNotEmpty) {
        await _batchStoreTransactions(newTransactions, walletContext);

        final controller = _streamControllers[asset.id];
        if (controller != null && !controller.isClosed) {
          for (final tx in newTransactions) {
            controller.add(tx);
          }
        }
      }
    } catch (_) {
      if (!_pollingTimers.containsKey(asset.id) ||
          !_isWalletContextCurrentSync(walletContext)) {
        return;
      }

      if (retryCount < _maxPollingRetries) {
        final delaySeconds = math.pow(2, retryCount).toInt();
        await Future<void>.delayed(
          Duration(seconds: delaySeconds),
          () => _pollNewTransactions(asset, walletContext, retryCount + 1),
        );
      }
    }
  }

  Future<void> _startPolling(
    Asset asset,
    WalletOperationContext walletContext,
  ) async {
    _stopPolling(asset.id);
    if (!_isWalletContextCurrentSync(walletContext)) return;

    try {
      // Prefer balance event stream when supported; otherwise, use timer
      // polling. ALL TRC-20 assets go straight to timer polling: gasless
      // custody activity never fires KDF EOA balance events (a dead end for
      // custody-first users), and detecting gasless-ness from pubkeys here is
      // unreliable at startup (stale hydrated cache, transient activation
      // errors) — timer polling degrades gracefully for non-gasless TRC-20,
      // while a misrouted gasless asset would never see its history update.
      // _custodyBalanceChanged re-evaluates gasless-ness on every tick.
      if (!_supportsBalanceStreaming(asset) ||
          await _isGaslessTrc20(asset, walletContext)) {
        _startTimerPolling(asset, walletContext);
        return;
      }

      final balanceSubscription = await _eventStreamingManager
          .subscribeToBalance(coin: asset.id.id);
      if (!await _isWalletContextCurrent(walletContext)) {
        await balanceSubscription.cancel();
        return;
      }

      _balanceFallbackSubscriptions[asset.id] = balanceSubscription
        ..onData((balanceEvent) {
          if (!_isWalletContextCurrentSync(walletContext)) return;
          if (balanceEvent.coin != asset.id.id) return;

          _syncHistoryIfBalanceChanged(
            asset,
            balance: balanceEvent.balance,
            walletContext: walletContext,
          ).ignore();
        })
        ..onError((Object error, StackTrace stackTrace) {
          _startTimerPolling(asset, walletContext);
        })
        ..onDone(() {
          _startTimerPolling(asset, walletContext);
        });

      // Initial sync to ensure we have the latest data without
      // immediately resorting to history polling on every interval.
      unawaited(
        _pollBalanceAndSyncHistory(
          asset,
          force: true,
          walletContext: walletContext,
        ),
      );
    } catch (_) {
      _startTimerPolling(asset, walletContext);
    }
  }

  void _startTimerPolling(Asset asset, WalletOperationContext walletContext) {
    if (!_isWalletContextCurrentSync(walletContext)) return;
    final balanceSub = _balanceFallbackSubscriptions.remove(asset.id);
    if (balanceSub != null) {
      balanceSub.cancel().ignore();
    }
    _pollingTimers[asset.id]?.cancel();
    _pollingTimers[asset.id] = Timer.periodic(
      _defaultPollingInterval,
      (_) => _pollBalanceAndSyncHistory(
        asset,
        walletContext: walletContext,
      ).ignore(),
    );
    _pollBalanceAndSyncHistory(
      asset,
      force: true,
      walletContext: walletContext,
    ).ignore();
  }

  void _stopPolling(AssetId assetId) {
    _pollingTimers[assetId]?.cancel();
    _pollingTimers.remove(assetId);

    final balanceSub = _balanceFallbackSubscriptions.remove(assetId);
    if (balanceSub != null) {
      balanceSub.cancel().ignore();
    }

    _lastBalanceForPolling.remove(assetId);
    _lastCustodyBalanceForPolling.remove(assetId);
  }

  // Periodically refresh the most recent transactions to update confirmations
  void _startConfirmationsRefresh(
    Asset asset,
    WalletOperationContext walletContext,
  ) {
    // Cancel any existing timer first
    _confirmationsTimers[asset.id]?.cancel();

    _confirmationsTimers[asset.id] = Timer.periodic(
      _defaultPollingInterval,
      (_) => _refreshRecentConfirmations(asset, walletContext),
    );

    // Kick off an immediate refresh
    _refreshRecentConfirmations(asset, walletContext).ignore();
  }

  void _stopConfirmationsRefresh(AssetId assetId) {
    _confirmationsTimers[assetId]?.cancel();
    _confirmationsTimers.remove(assetId);
  }

  Future<void> _refreshRecentConfirmations(
    Asset asset,
    WalletOperationContext walletContext,
  ) async {
    if (!_isWalletContextCurrentSync(walletContext)) return;

    try {
      // Avoid hammering the backend
      await _rateLimiter.throttle();
      await _requireWalletContextCurrent(walletContext);

      // Ensure asset is active (no-op if already active)
      await _ensureAssetActivated(asset, walletContext);

      final strategy = _strategyFactory.forAsset(asset);
      // Fetch the first page to update the most recent txs' confirmations
      final response = await strategy.fetchTransactionHistory(
        _client,
        asset,
        const PagePagination(pageNumber: 1, itemsPerPage: _maxBatchSize),
      );
      await _requireWalletContextCurrent(walletContext);

      if (response.transactions.isEmpty) return;

      final transactions = response.transactions
          .map((tx) => tx.asTransaction(asset.id))
          .toList();

      await _batchStoreTransactions(transactions, walletContext);

      final controller = _streamControllers[asset.id];
      if (controller != null && !controller.isClosed) {
        for (final tx in transactions) {
          controller.add(tx);
        }
      }
    } catch (_) {
      // Best-effort refresh; swallow transient errors
    }
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _walletGeneration++;

    await _authSubscription?.cancel();

    for (final sub in _txHistorySubscriptions.values) {
      await sub.cancel();
    }
    _txHistorySubscriptions.clear();

    final timers = _pollingTimers.values.toList();
    _pollingTimers.clear();
    for (final timer in timers) {
      timer.cancel();
    }

    final controllers = _streamControllers.values.toList();
    _streamControllers.clear();
    for (final controller in controllers) {
      await controller.close();
    }

    _syncInProgress.clear();

    _activatedThisSession.clear();

    // Cancel confirmations refresh timers
    for (final timer in _confirmationsTimers.values) {
      timer.cancel();
    }
    _confirmationsTimers.clear();

    // Release the backing store when it owns one. Opt-in rather than part of
    // TransactionStorage, so the in-memory implementation and the test fakes
    // are unaffected.
    if (_storage case final ClosableTransactionStorage closable) {
      await closable.close();
    }
  }
}

class _RateLimiter {
  _RateLimiter(this.interval);
  final Duration interval;
  DateTime? _lastCall;

  Future<void> throttle() async {
    if (_lastCall != null) {
      final timeSinceLastCall = DateTime.now().difference(_lastCall!);
      if (timeSinceLastCall < interval) {
        await Future<void>.delayed(interval - timeSinceLastCall);
      }
    }
    _lastCall = DateTime.now();
  }
}
