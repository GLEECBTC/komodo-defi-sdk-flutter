import 'package:komodo_defi_sdk/src/transaction_history/transaction_cache_retention.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_history_cache_policy.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_merge_utils.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_record_codec.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_storage_key.dart';
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
  Future<CachedTransactionPage> getTransactions(
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

/// A slice of retained cache data, never a provider history page.
///
/// The cache may contain holes or omit older rows. Its count is not a network
/// total, and its internal IDs must never be substituted for provider cursors.
class CachedTransactionPage {
  /// Describes retained rows without asserting provider completeness.
  const CachedTransactionPage({
    required this.transactions,
    required this.cachedCount,
  });

  /// Cached transactions in newest-first display order.
  final List<Transaction> transactions;

  /// Total rows retained for this wallet and asset, including other slices.
  final int cachedCount;
}

/// Bounded, reconstructible history used when persistence is off or
/// unavailable.
class InMemoryTransactionStorage implements TransactionStorage {
  /// Creates a bounded memory cache.
  InMemoryTransactionStorage({
    this.policy = const TransactionHistoryCachePolicy(),
  }) : _retention = TransactionCacheRetention(policy);

  /// Creates a memory cache with the default finite limits.
  static Future<InMemoryTransactionStorage> create() async =>
      InMemoryTransactionStorage();

  /// Retention limits applied after each batch.
  final TransactionHistoryCachePolicy policy;
  final _mutex = Mutex();
  final TransactionCacheRetention _retention;
  final _rows = <String, (String, Transaction)>{};
  final _scopes = <String, AssetTransactionHistoryId>{};

  /// Logical payload and index bytes charged against the configured budget.
  int get logicalBytes => _retention.logicalBytes;

  String _scope(WalletId walletId, AssetId assetId) {
    final scope = TransactionStorageKey.prefix(walletId, assetId);
    if (_retention.scopeAccess.containsKey(scope)) {
      _scopes[scope] = AssetTransactionHistoryId(walletId, assetId);
      _retention.touch(scope, DateTime.now().microsecondsSinceEpoch);
    }
    return scope;
  }

  List<Transaction> _ordered(String scope) =>
      _rows.values.where((row) => row.$1 == scope).map((row) => row.$2).toList()
        ..sort((a, b) {
          final byTimestamp = b.timestamp.compareTo(a.timestamp);
          return byTimestamp != 0
              ? byTimestamp
              : b.internalId.compareTo(a.internalId);
        });

  @override
  Future<void> storeTransaction(Transaction transaction, WalletId walletId) =>
      storeTransactions([transaction], walletId);

  @override
  Future<void> storeTransactions(
    List<Transaction> transactions,
    WalletId walletId,
  ) async {
    if (transactions.any((transaction) => transaction.internalId.isEmpty)) {
      throw TransactionStorageException(
        'Transaction internal ID cannot be empty',
      );
    }
    await _mutex.protect(() async {
      for (final incoming in transactions) {
        final scope = _scope(walletId, incoming.assetId);
        _scopes[scope] = AssetTransactionHistoryId(walletId, incoming.assetId);
        final key =
            '$scope${TransactionStorageKey.idTokenFor(incoming.internalId)}';
        final previous = _rows[key]?.$2;
        final merged = previous == null
            ? incoming
            : TransactionMergeUtils.mergeTransactionFields(previous, incoming);
        final orderKey = TransactionStorageKey.build(
          prefix: scope,
          timestamp: merged.timestamp,
          internalId: merged.internalId,
        );
        final record = TransactionRecordCodec.encode(merged);
        _rows[key] = (scope, merged);
        _retention.put(
          key,
          TransactionCacheEntry(
            scope: scope,
            orderKey: orderKey,
            logicalBytes: TransactionCacheEntry.sizeOf(record, orderKey),
          ),
          DateTime.now().microsecondsSinceEpoch,
        );
      }
      for (final key in _retention.prune()) {
        _rows.remove(key);
      }
      _scopes.removeWhere(
        (scope, _) => !_retention.scopeAccess.containsKey(scope),
      );
    });
  }

  @override
  Future<CachedTransactionPage> getTransactions(
    AssetId assetId,
    WalletId walletId, {
    String? fromId,
    int? pageNumber,
    int limit = 10,
  }) => _mutex.protect(() async {
    final ordered = _ordered(_scope(walletId, assetId));
    var start = 0;
    if (fromId != null && ordered.isNotEmpty) {
      final index = ordered.indexWhere((row) => row.internalId == fromId);
      if (index == -1) {
        throw TransactionStorageException('Starting transaction not found');
      }
      start = index + 1;
    } else if (pageNumber != null && pageNumber > 1) {
      start = (pageNumber - 1) * limit;
    }
    return CachedTransactionPage(
      transactions: limit <= 0
          ? const []
          : ordered.skip(start).take(limit).toList(growable: false),
      cachedCount: ordered.length,
    );
  });

  @override
  Future<Transaction?> getTransactionById(String internalId) =>
      _mutex.protect(() async {
        for (final row in _rows.values) {
          if (row.$2.internalId == internalId) {
            _retention.touch(row.$1, DateTime.now().microsecondsSinceEpoch);
            return row.$2;
          }
        }
        return null;
      });

  @override
  Future<void> clearTransactions(AssetId assetId, WalletId walletId) =>
      _mutex.protect(() async => _removeScope(_scope(walletId, assetId)));

  void _removeScope(String scope) {
    final keys = _rows.entries
        .where((entry) => entry.value.$1 == scope)
        .map((entry) => entry.key)
        .toList();
    for (final key in keys) {
      _rows.remove(key);
      _retention.remove(key);
    }
    _retention.scopeAccess.remove(scope);
    _scopes.remove(scope);
  }

  /// Deletes the wallet's cache without touching its unresolved transfer
  /// journal.
  Future<void> purgeWallet(WalletId walletId) => _mutex.protect(() async {
    final prefix = TransactionStorageKey.walletPrefix(walletId);
    for (final scope in _scopes.keys.toList()) {
      if (scope.startsWith(prefix)) _removeScope(scope);
    }
  });

  @override
  Future<String?> getLatestTransactionId(AssetId assetId, WalletId walletId) =>
      _mutex.protect(
        () async => _ordered(_scope(walletId, assetId)).firstOrNull?.internalId,
      );

  @override
  Future<StorageStats> getStats() => _mutex.protect(() async {
    if (_rows.isEmpty) {
      throw TransactionStorageException('No transactions available');
    }
    final transactions = _rows.values.map((row) => row.$2).toList();
    return StorageStats(
      totalTransactions: transactions.length,
      transactionsPerAsset: {
        for (final scope in _scopes.entries)
          if (_retention.scopeAccess.containsKey(scope.key))
            scope.value: _ordered(scope.key).length,
      },
      oldestTransaction: transactions
          .map((tx) => tx.timestamp)
          .reduce((a, b) => a.isBefore(b) ? a : b),
      newestTransaction: transactions
          .map((tx) => tx.timestamp)
          .reduce((a, b) => a.isAfter(b) ? a : b),
    );
  });
}

/// Invalid cache operations, such as an unknown internal pagination cursor.
class TransactionStorageException implements Exception {
  /// Describes a cache operation failure.
  TransactionStorageException(this.message, [this.cause]);

  /// Human-readable description that must exclude transaction/secret contents.
  final String message;

  /// Optional underlying cause supplied by the caller.
  final Object? cause;

  @override
  String toString() =>
      'TransactionStorageException: $message'
      '${cause != null ? ' ($cause)' : ''}';
}

/// Counts and timestamp bounds of retained cache rows.
class StorageStats {
  /// Summarizes retained rows without implying a complete network history.
  StorageStats({
    required this.totalTransactions,
    required this.transactionsPerAsset,
    required this.oldestTransaction,
    required this.newestTransaction,
  });

  /// Number of rows retained across the cache.
  final int totalTransactions;

  /// Counts for scopes whose identity is known in this process.
  final Map<AssetTransactionHistoryId, int> transactionsPerAsset;

  /// Oldest timestamp among retained rows.
  final DateTime oldestTransaction;

  /// Newest timestamp among retained rows.
  final DateTime newestTransaction;
}
