import 'dart:async';
import 'dart:math' as math;

import 'package:komodo_defi_framework/komodo_defi_framework.dart'
    show BalanceEvent;
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/src/_internal_exports.dart';
import 'package:komodo_defi_sdk/src/activation/activation_exceptions.dart';
import 'package:komodo_defi_sdk/src/assets/asset_history_storage.dart';
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
    String? tronProApiKey,
  }) : _storage = storage ?? TransactionStorage.defaultForPlatform(),
       _strategyFactory = TransactionHistoryStrategyFactory(
         pubkeyManager,
         _auth,
         tronProApiKey: tronProApiKey,
       ),
       _eventStreamingManager = eventStreamingManager,
       _assetHistoryStorage = assetHistoryStorage ?? AssetHistoryStorage() {
    // Subscribe to auth changes directly in constructor
    _authSubscription = _auth.authStateChanges.listen((user) {
      if (user == null) {
        _stopAllStreaming();
      }
    });
  }

  final ApiClient _client;
  final KomodoDefiLocalAuth _auth;
  final IAssetProvider _assetProvider;
  final SharedActivationCoordinator _activationCoordinator;
  final TransactionStorage _storage;
  final EventStreamingManager _eventStreamingManager;
  final AssetHistoryStorage _assetHistoryStorage;

  final _streamControllers = <AssetId, StreamController<Transaction>>{};
  final _txHistorySubscriptions = <AssetId, StreamSubscription<dynamic>>{};
  final _pollingTimers = <AssetId, Timer>{};
  // Periodic confirmations refresh timers while streaming is healthy
  final _confirmationsTimers = <AssetId, Timer>{};
  final _balanceFallbackSubscriptions =
      <AssetId, StreamSubscription<BalanceEvent>>{};
  final _lastBalanceForPolling = <AssetId, BalanceInfo>{};
  final _syncInProgress = <AssetId>{};
  final _rateLimiter = _RateLimiter(const Duration(milliseconds: 500));

  static const _defaultPollingInterval = Duration(seconds: 30);
  static const _maxPollingRetries = 3;
  static const _maxBatchSize = 50;

  bool _isDisposed = false;
  StreamSubscription<KdfUser?>? _authSubscription;

  final TransactionHistoryStrategyFactory _strategyFactory;

  // Streaming capability helpers based on asset properties
  bool _supportsBalanceStreaming(Asset asset) => asset.supportsBalanceStreaming;

  bool _supportsTxHistoryStreaming(Asset asset) =>
      asset.supportsTxHistoryStreaming;

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

      // Default to first page if no pagination specified
      pagination ??= const PagePagination(
        pageNumber: 1,
        itemsPerPage: _maxBatchSize,
      );

      // Optimization: Check if this is a newly created wallet (not imported)
      final user = await _auth.currentUser;
      if (user != null &&
          pagination is PagePagination &&
          pagination.pageNumber == 1) {
        final previouslyEnabledAssets = await _assetHistoryStorage
            .getWalletAssets(user.walletId);
        final isFirstTimeEnabling = !previouslyEnabledAssets.contains(
          asset.id.id,
        );

        // Check metadata to determine if this was an imported wallet
        // Only optimize for genuinely new wallets, not imported ones
        final isImported = user.metadata['isImported'] == true;
        final isNewWallet = previouslyEnabledAssets.isEmpty && !isImported;

        // For newly created wallets (not imported) on first-time asset enablement,
        // assume empty transaction history to reduce RPC spam
        if (isFirstTimeEnabling && isNewWallet) {
          // Still need to activate the asset
          await _ensureAssetActivated(asset);

          // Mark asset as seen after activation
          await _assetHistoryStorage.addAssetToWallet(
            user.walletId,
            asset.id.id,
          );

          return TransactionPage(
            transactions: const [],
            total: 0,
            currentPage: 1,
            totalPages: 1,
          );
        }
      }

      // First try to get from local storage
      final localPage = await _storage.getTransactions(
        asset.id,
        await _getCurrentWalletId(),
        fromId: pagination is TransactionBasedPagination
            ? pagination.fromId
            : null,
        pageNumber: pagination is PagePagination ? pagination.pageNumber : null,
        limit: pagination.limit ?? _maxBatchSize,
      );

      // If we have enough local data and it's not a first page request, return it
      if (localPage.transactions.isNotEmpty &&
          (pagination is PagePagination && pagination.pageNumber > 1 ||
              pagination is TransactionBasedPagination)) {
        return localPage;
      }

      // Skip activation check if we have local transaction history, as this
      // implies the asset was previously activated. This reduces RPC spam when
      // opening the coin details page repeatedly for already-activated assets.
      final hasLocalHistory = localPage.transactions.isNotEmpty;

      if (!hasLocalHistory) {
        await _ensureAssetActivated(asset);
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

      // Convert API response to domain model
      final transactions = response.transactions
          .map((tx) => tx.asTransaction(asset.id))
          .toList();

      // Store in local storage efficiently
      await _batchStoreTransactions(transactions);

      return TransactionPage(
        transactions: transactions,
        total: response.total,
        nextPageId: response.fromId,
        currentPage: response.pageNumber ?? 1,
        totalPages: response.totalPages,
      );
    } catch (e) {
      if (e is TransactionStorageException) {
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

    try {
      await _ensureAssetActivated(asset);
    } catch (e) {
      if (e is ActivationFailedException) {
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

    // First try to get any cached transactions
    final localPage = await _storage.getTransactions(
      asset.id,
      await _getCurrentWalletId(),
      limit: _maxBatchSize,
    );

    if (localPage.transactions.isNotEmpty) {
      yield localPage.transactions;
    }

    String? fromId;
    var hasMore = true;
    var retryCount = 0;
    const maxRetries = 3;

    while (hasMore && !_isDisposed) {
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

        if (response.transactions.isEmpty) {
          hasMore = false;
          continue;
        }

        final transactions = response.transactions
            .map((tx) => tx.asTransaction(asset.id))
            .toList();

        await _batchStoreTransactions(transactions);
        yield transactions;

        fromId = response.fromId;

        if (response.transactions.length < _maxBatchSize || fromId == null) {
          hasMore = false;
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      } catch (e) {
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
    final reconciler = TransactionListReconciler();
    var merged = <Transaction>[];
    var emittedInitial = false;

    await for (final batch in getTransactionsStreamed(asset)) {
      final incoming = transform == null
          ? batch
          : batch.map(transform).toList(growable: false);
      merged = reconciler.merge(existing: merged, incoming: incoming);
      emittedInitial = true;
      yield List<Transaction>.unmodifiable(merged);
    }

    if (!emittedInitial) {
      yield const <Transaction>[];
    }

    await for (final transaction in watchTransactions(asset)) {
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
          if (!_streamControllers[asset.id]!.hasListener) {
            _stopStreaming(asset.id);
            await _streamControllers[asset.id]?.close();
            _streamControllers.remove(asset.id);
          }
        },
      ),
    );

    return controller.stream;
  }

  @override
  Future<void> syncTransactionHistory(Asset asset) async {
    if (_isDisposed || _syncInProgress.contains(asset.id)) return;
    _syncInProgress.add(asset.id);

    try {
      final strategy = _strategyFactory.forAsset(asset);
      var fromId = await _storage.getLatestTransactionId(
        asset.id,
        await _getCurrentWalletId(),
      );
      var hasMore = true;

      while (hasMore && !_isDisposed) {
        await _rateLimiter.throttle();

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

        if (response.transactions.isEmpty) {
          hasMore = false;
          continue;
        }

        final transactions = response.transactions
            .map((tx) => tx.asTransaction(asset.id))
            .toList();

        await _batchStoreTransactions(transactions);
        fromId = response.fromId;

        if (response.transactions.length < _maxBatchSize) {
          hasMore = false;
        }
      }
    } finally {
      _syncInProgress.remove(asset.id);
    }
  }

  @override
  Future<void> clearTransactionHistory(Asset asset) async {
    if (_isDisposed) return;

    await _storage.clearTransactions(asset.id, await _getCurrentWalletId());
    _stopStreaming(asset.id);
    await _streamControllers[asset.id]?.close();
    _streamControllers.remove(asset.id);
  }

  Future<void> _ensureAssetActivated(Asset asset) async {
    final activationResult = await _activationCoordinator.activateAsset(asset);
    if (activationResult.isFailure) {
      throw ActivationFailedException(
        assetId: asset.id,
        message: activationResult.errorMessage ?? 'Unknown activation error',
        errorCode: 'ACTIVATION_FAILED',
        originalError: activationResult.errorMessage,
      );
    }
  }

  Future<WalletId> _getCurrentWalletId() async {
    final currentUser = await _auth.currentUser;
    if (currentUser == null) {
      throw StateError('User is not logged in');
    }
    return currentUser.walletId;
  }

  Future<void> _batchStoreTransactions(List<Transaction> transactions) async {
    if (transactions.isEmpty) return;

    try {
      await _storage.storeTransactions(
        transactions,
        await _getCurrentWalletId(),
      );
    } catch (e) {
      throw Exception('Failed to store transactions batch: $e');
    }
  }

  Future<void> _startStreaming(Asset asset) async {
    // Ensure we don't duplicate subscriptions
    _stopStreaming(asset.id);

    // Ensure asset is activated before subscribing
    try {
      await _ensureAssetActivated(asset);
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
        await _startPolling(asset);
        return;
      }
      final txHistoryStreamSubscription = await _eventStreamingManager
          .subscribeToTxHistory(coin: asset.id.id);

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
        if (hasFallenBack || _isDisposed) return;
        hasFallenBack = true;

        if (_txHistorySubscriptions[asset.id] == txHistoryStreamSubscription) {
          _txHistorySubscriptions.remove(asset.id);
        }

        try {
          await txHistoryStreamSubscription.cancel();
        } catch (_) {}

        await _startPolling(asset);
      }

      _txHistorySubscriptions[asset.id] = txHistoryStreamSubscription
        ..onData((txHistoryEvent) async {
          if (_isDisposed) return;

          // Verify the event is for the correct coin
          if (txHistoryEvent.coin != asset.id.id) return;

          // Process new transactions
          final transactions = txHistoryEvent.transactions
              .map((tx) => tx.asTransaction(asset.id))
              .toList();

          if (transactions.isEmpty) return;

          // Store transactions in local storage
          await _batchStoreTransactions(transactions);

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
      _startConfirmationsRefresh(asset);
    } catch (_) {
      await _startPolling(asset);
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
    BalanceInfo? balance,
    bool force = false,
  }) async {
    if (_isDisposed) return;
    if (!_isPollingActive(asset.id)) return;

    var shouldSync = force;

    if (balance != null) {
      final hasChanged = _updateLastKnownBalance(asset.id, balance);
      shouldSync = shouldSync || hasChanged;
    }

    if (!shouldSync) return;

    await _pollNewTransactions(asset);
  }

  Future<void> _pollBalanceAndSyncHistory(
    Asset asset, {
    bool force = false,
  }) async {
    if (_isDisposed) return;

    try {
      await _ensureAssetActivated(asset);
      final response = await _client.rpc.wallet.myBalance(coin: asset.id.id);
      await _syncHistoryIfBalanceChanged(
        asset,
        balance: response.balance,
        force: force,
      );
    } catch (_) {
      if (force) {
        await _pollNewTransactions(asset);
      }
    }
  }

  Future<void> _pollNewTransactions(Asset asset, [int retryCount = 0]) async {
    if (_isDisposed) return;

    try {
      await _ensureAssetActivated(asset);
      final strategy = _strategyFactory.forAsset(asset);
      final latestId = await _storage.getLatestTransactionId(
        asset.id,
        await _getCurrentWalletId(),
      );

      final response = await strategy.fetchTransactionHistory(
        _client,
        asset,
        latestId != null
            ? TransactionBasedPagination(
                fromId: latestId,
                itemCount: _maxBatchSize,
              )
            : const PagePagination(pageNumber: 1, itemsPerPage: _maxBatchSize),
      );

      if (!_isPollingActive(asset.id)) return;

      if (response.transactions.isNotEmpty) {
        final newTransactions = response.transactions
            .map((tx) => tx.asTransaction(asset.id))
            .toList();

        await _batchStoreTransactions(newTransactions);

        final controller = _streamControllers[asset.id];
        if (controller != null && !controller.isClosed) {
          for (final tx in newTransactions) {
            controller.add(tx);
          }
        }
      }
    } catch (_) {
      if (!_pollingTimers.containsKey(asset.id)) return;

      if (retryCount < _maxPollingRetries) {
        final delaySeconds = math.pow(2, retryCount).toInt();
        await Future<void>.delayed(
          Duration(seconds: delaySeconds),
          () => _pollNewTransactions(asset, retryCount + 1),
        );
      }
    }
  }

  Future<void> _startPolling(Asset asset) async {
    _stopPolling(asset.id);

    try {
      // Prefer balance event stream when supported; otherwise, use timer polling
      if (!_supportsBalanceStreaming(asset)) {
        _startTimerPolling(asset);
        return;
      }

      final balanceSubscription = await _eventStreamingManager
          .subscribeToBalance(coin: asset.id.id);

      _balanceFallbackSubscriptions[asset.id] = balanceSubscription
        ..onData((balanceEvent) {
          if (_isDisposed) return;
          if (balanceEvent.coin != asset.id.id) return;

          _syncHistoryIfBalanceChanged(
            asset,
            balance: balanceEvent.balance,
          ).ignore();
        })
        ..onError((Object error, StackTrace stackTrace) {
          _startTimerPolling(asset);
        })
        ..onDone(() {
          _startTimerPolling(asset);
        });

      // Initial sync to ensure we have the latest data without
      // immediately resorting to history polling on every interval.
      unawaited(_pollBalanceAndSyncHistory(asset, force: true));
    } catch (_) {
      _startTimerPolling(asset);
    }
  }

  void _startTimerPolling(Asset asset) {
    final balanceSub = _balanceFallbackSubscriptions.remove(asset.id);
    if (balanceSub != null) {
      balanceSub.cancel().ignore();
    }
    _pollingTimers[asset.id]?.cancel();
    _pollingTimers[asset.id] = Timer.periodic(
      _defaultPollingInterval,
      (_) => _pollBalanceAndSyncHistory(asset).ignore(),
    );
    _pollBalanceAndSyncHistory(asset, force: true).ignore();
  }

  void _stopPolling(AssetId assetId) {
    _pollingTimers[assetId]?.cancel();
    _pollingTimers.remove(assetId);

    final balanceSub = _balanceFallbackSubscriptions.remove(assetId);
    if (balanceSub != null) {
      balanceSub.cancel().ignore();
    }

    _lastBalanceForPolling.remove(assetId);
  }

  // Periodically refresh the most recent transactions to update confirmations
  void _startConfirmationsRefresh(Asset asset) {
    // Cancel any existing timer first
    _confirmationsTimers[asset.id]?.cancel();

    _confirmationsTimers[asset.id] = Timer.periodic(
      _defaultPollingInterval,
      (_) => _refreshRecentConfirmations(asset),
    );

    // Kick off an immediate refresh
    _refreshRecentConfirmations(asset).ignore();
  }

  void _stopConfirmationsRefresh(AssetId assetId) {
    _confirmationsTimers[assetId]?.cancel();
    _confirmationsTimers.remove(assetId);
  }

  Future<void> _refreshRecentConfirmations(Asset asset) async {
    if (_isDisposed) return;

    try {
      // Avoid hammering the backend
      await _rateLimiter.throttle();

      // Ensure asset is active (no-op if already active)
      await _ensureAssetActivated(asset);

      final strategy = _strategyFactory.forAsset(asset);
      // Fetch the first page to update the most recent txs' confirmations
      final response = await strategy.fetchTransactionHistory(
        _client,
        asset,
        const PagePagination(pageNumber: 1, itemsPerPage: _maxBatchSize),
      );

      if (_isDisposed) return;

      if (response.transactions.isEmpty) return;

      final transactions = response.transactions
          .map((tx) => tx.asTransaction(asset.id))
          .toList();

      await _batchStoreTransactions(transactions);

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

    // Cancel confirmations refresh timers
    for (final timer in _confirmationsTimers.values) {
      timer.cancel();
    }
    _confirmationsTimers.clear();
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
