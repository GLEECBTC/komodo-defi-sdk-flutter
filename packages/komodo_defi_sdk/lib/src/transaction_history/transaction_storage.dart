import 'package:collection/collection.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_merge_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mutex/mutex.dart';

/// Core interface for transaction history storage implementations
abstract interface class TransactionStorage {
  factory TransactionStorage.defaultForPlatform() =>
      InMemoryTransactionStorage();

  /// Store a new transaction
  Future<void> storeTransaction(Transaction transaction, WalletId walletId);

  /// Store multiple transactions in batch
  Future<void> storeTransactions(
    List<Transaction> transactions,
    WalletId walletId,
  );

  /// Retrieve transactions for an asset with pagination
  Future<TransactionPage> getTransactions(
    AssetId assetId,
    WalletId walletId, {
    String? fromId,
    int? pageNumber,
    int limit = 10,
  });

  /// Get a specific transaction by internal ID
  Future<Transaction?> getTransactionById(String internalId);

  /// Clear stored transactions for an asset
  Future<void> clearTransactions(AssetId assetId, WalletId walletId);

  /// Get latest transaction's internal ID for an asset
  Future<String?> getLatestTransactionId(AssetId assetId, WalletId walletId);

  /// Get storage statistics
  Future<StorageStats> getStats();
}

class InMemoryTransactionStorage implements TransactionStorage {
  /// Creates an in-memory store.
  ///
  /// [maxTransactionsPerAsset] caps how many transactions are retained per
  /// (wallet, asset) pair, evicting oldest-first. Defaults to `null`
  /// (unbounded), which is the historical behaviour.
  InMemoryTransactionStorage({int? maxTransactionsPerAsset})
    : _storage = {},
      _maxTransactionsPerAsset = maxTransactionsPerAsset;

  static Future<InMemoryTransactionStorage> create() async =>
      InMemoryTransactionStorage();

  final _mutex = Mutex();
  final Map<AssetTransactionHistoryId, Map<String, Transaction>> _storage;
  final int? _maxTransactionsPerAsset;

  /// Orders transactions newest-first, with `internalId` descending as a stable
  /// tiebreaker for equal timestamps.
  ///
  /// This used to be a `SplayTreeMap` comparator that resolved each key through
  /// a map captured when the tree was built. That made the tree's ordering
  /// depend on a snapshot of its own contents, so any lookup for a key added
  /// after construction - `existingMap[newInternalId]` on the second batch for
  /// an asset, or `containsKey` in [getTransactionById] - threw
  /// `Transaction not found in comparison`. In practice that meant every page
  /// of history after the first failed to store. Ordering is now applied on
  /// read over a plain map, which cannot go stale.
  static int _compareTransactions(Transaction a, Transaction b) {
    final byTimestamp = b.timestamp.compareTo(a.timestamp);
    if (byTimestamp != 0) return byTimestamp;
    return b.internalId.compareTo(a.internalId);
  }

  /// Returns this asset's transactions in display order.
  ///
  /// The caller must already hold [_mutex].
  List<Transaction> _orderedLocked(AssetTransactionHistoryId assetHistoryId) {
    final assetTransactions = _storage[assetHistoryId];
    if (assetTransactions == null || assetTransactions.isEmpty) {
      return const [];
    }
    return assetTransactions.values.toList()..sort(_compareTransactions);
  }

  /// Merges [incoming] into this asset's map, preserving the monotonic
  /// balance-component semantics of
  /// [TransactionMergeUtils.mergeTransactionFields].
  ///
  /// The caller must already hold [_mutex].
  void _mergeIntoLocked(
    AssetTransactionHistoryId assetHistoryId,
    Iterable<Transaction> incoming,
  ) {
    final assetTransactions = _storage.putIfAbsent(
      assetHistoryId,
      () => <String, Transaction>{},
    );
    for (final transaction in incoming) {
      assetTransactions.update(
        transaction.internalId,
        (existing) =>
            TransactionMergeUtils.mergeTransactionFields(existing, transaction),
        ifAbsent: () => transaction,
      );
    }
  }

  @override
  Future<void> storeTransaction(
    Transaction transaction,
    WalletId walletId,
  ) async {
    if (transaction.internalId.isEmpty) {
      throw TransactionStorageException(
        'Transaction internal ID cannot be empty',
      );
    }

    try {
      await _mutex.protect(() async {
        final assetHistoryId = AssetTransactionHistoryId(
          walletId,
          transaction.assetId,
        );
        _mergeIntoLocked(assetHistoryId, [transaction]);
        _enforceStorageLimitLocked(transaction.assetId, walletId);
      });
    } catch (e) {
      throw TransactionStorageException('Failed to store transaction', e);
    }
  }

  @override
  Future<void> storeTransactions(
    List<Transaction> transactions,
    WalletId user,
  ) async {
    if (transactions.isEmpty) return;

    try {
      await _mutex.protect(() async {
        final grouped = groupBy(transactions, (tx) => tx.assetId);

        for (final entry in grouped.entries) {
          // Collapse duplicates within the batch first so two perspectives of
          // the same transfer arriving on one page merge rather than overwrite.
          final newTxMap = <String, Transaction>{};
          for (final transaction in entry.value) {
            newTxMap.update(
              transaction.internalId,
              (existing) => TransactionMergeUtils.mergeTransactionFields(
                existing,
                transaction,
              ),
              ifAbsent: () => transaction,
            );
          }
          _mergeIntoLocked(
            AssetTransactionHistoryId(user, entry.key),
            newTxMap.values,
          );
        }

        // Already inside `_mutex.protect`: call the non-locking variant, or
        // this deadlocks permanently. See [_enforceStorageLimitLocked].
        for (final assetId in grouped.keys) {
          _enforceStorageLimitLocked(assetId, user);
        }
      });
    } catch (e) {
      throw TransactionStorageException('Failed to store transactions', e);
    }
  }

  @override
  Future<TransactionPage> getTransactions(
    AssetId assetId,
    WalletId user, {
    String? fromId,
    int? pageNumber,
    int limit = 10,
  }) async {
    return _mutex.protect(() async {
      final assetTransactionsId = AssetTransactionHistoryId(user, assetId);
      var transactions = _orderedLocked(assetTransactionsId);
      final total = transactions.length;

      if (total == 0) {
        return TransactionPage(
          transactions: const [],
          total: 0,
          currentPage: pageNumber ?? 1,
          totalPages: 0,
        );
      }

      if (fromId != null) {
        final startIndex = transactions.indexWhere(
          (t) => t.internalId == fromId,
        );
        if (startIndex == -1) {
          throw TransactionStorageException('Starting transaction not found');
        }
        transactions = transactions.sublist(startIndex + 1);
      } else if (pageNumber != null && pageNumber > 1) {
        final startIndex = (pageNumber - 1) * limit;
        if (startIndex >= transactions.length) {
          transactions = [];
        } else {
          transactions = transactions.sublist(startIndex);
        }
      }

      final page = transactions.take(limit).toList();
      final totalPages = (total / limit).ceil();

      return TransactionPage(
        transactions: page,
        total: total,
        nextPageId: page.lastOrNull?.internalId,
        currentPage: pageNumber ?? 1,
        totalPages: totalPages,
      );
    });
  }

  @override
  Future<Transaction?> getTransactionById(String internalId) async {
    return _mutex.protect(() async {
      for (final assetTransactions in _storage.values) {
        if (assetTransactions.containsKey(internalId)) {
          return assetTransactions[internalId];
        }
      }
      return null;
    });
  }

  @override
  Future<void> clearTransactions(AssetId assetId, WalletId user) async {
    await _mutex.protect(() async {
      final assetTxHistoryId = AssetTransactionHistoryId(user, assetId);
      _storage.remove(assetTxHistoryId);
    });
  }

  @override
  Future<String?> getLatestTransactionId(AssetId assetId, WalletId user) async {
    return _mutex.protect(() async {
      final assetTxHistoryId = AssetTransactionHistoryId(user, assetId);
      final transactions = _orderedLocked(assetTxHistoryId);
      if (transactions.isEmpty) return null;
      return transactions.first.internalId;
    });
  }

  /// Evicts the oldest transactions once an asset exceeds the configured cap.
  ///
  /// The caller **must** already hold [_mutex]. `package:mutex`'s [Mutex] is a
  /// write-only [ReadWriteMutex] and is not reentrant: re-acquiring it from
  /// inside a protected section blocks on a future that only `release()` can
  /// complete, and `release()` is in the `finally` that is itself waiting. The
  /// result is a permanent hang, not an exception, so every later call on this
  /// instance would block forever too.
  void _enforceStorageLimitLocked(AssetId assetId, WalletId user) {
    final maxTransactions = _maxTransactionsPerAsset;
    if (maxTransactions == null) return;

    final assetTxHistoryId = AssetTransactionHistoryId(user, assetId);
    final assetTransactions = _storage[assetTxHistoryId];
    if (assetTransactions == null) return;

    if (assetTransactions.length > maxTransactions) {
      final excess = assetTransactions.length - maxTransactions;
      final sortedEntries = assetTransactions.entries.toList()
        ..sort((a, b) {
          final timestampComparison = a.value.timestamp.compareTo(
            b.value.timestamp,
          );
          return timestampComparison != 0
              ? timestampComparison
              : a.value.internalId.compareTo(b.value.internalId);
        });

      final keysToRemove = sortedEntries
          .take(excess)
          .map((e) => e.key)
          .toList();

      for (final key in keysToRemove) {
        assetTransactions.remove(key);
      }
    }
  }

  @override
  Future<StorageStats> getStats() async {
    return _mutex.protect(() async {
      final allTransactions = _storage.values
          .expand((assetTransactions) => assetTransactions.values)
          .toList();

      if (allTransactions.isEmpty) {
        throw TransactionStorageException('No transactions available');
      }

      final totalTransactions = allTransactions.length;

      final transactionsPerAsset = _storage.map(
        (assetId, assetTransactions) =>
            MapEntry(assetId, assetTransactions.length),
      );

      final oldestTransaction = allTransactions
          .map((tx) => tx.timestamp)
          .reduce((a, b) => a.isBefore(b) ? a : b);

      final newestTransaction = allTransactions
          .map((tx) => tx.timestamp)
          .reduce((a, b) => a.isAfter(b) ? a : b);

      return StorageStats(
        totalTransactions: totalTransactions,
        transactionsPerAsset: transactionsPerAsset,
        oldestTransaction: oldestTransaction,
        newestTransaction: newestTransaction,
      );
    });
  }
}

class TransactionStorageException implements Exception {
  TransactionStorageException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() =>
      'TransactionStorageException: $message${cause != null ? ' ($cause)' : ''}';
}

class StorageStats {
  StorageStats({
    required this.totalTransactions,
    required this.transactionsPerAsset,
    required this.oldestTransaction,
    required this.newestTransaction,
  });

  final int totalTransactions;
  final Map<AssetTransactionHistoryId, int> transactionsPerAsset;
  final DateTime oldestTransaction;
  final DateTime newestTransaction;
}
