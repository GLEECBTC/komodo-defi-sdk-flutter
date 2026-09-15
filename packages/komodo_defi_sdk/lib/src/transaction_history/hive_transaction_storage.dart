import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'package:komodo_defi_sdk/src/transaction_history/history_cache_key_provider.dart';
import 'package:komodo_defi_sdk/src/transaction_history/history_cache_lease.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_cache_retention.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_history_cache_policy.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_merge_utils.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_order_index.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_record_codec.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_storage.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_storage_key.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mutex/mutex.dart';

/// A cache that can release its backing resources.
// ignore: one_member_abstracts
abstract interface class ClosableTransactionStorage {
  /// Flushes and releases this acquisition of the cache.
  Future<void> close();
}

/// Encrypted, bounded transaction cache owned by the SDK.
///
/// Hive encrypts values but not keys. Disk keys are therefore HMAC identifiers;
/// timestamps, wallet/asset scope and transaction IDs live inside encrypted
/// envelopes. Opening the cache rebuilds a bounded in-memory ordering index
/// from those envelopes. Transaction domain objects are decoded only on read.
///
/// Every acquisition of a box shares one index and a reference-counted owner.
/// On web an exclusive lease prevents another tab from maintaining a competing
/// Hive index. A tab without the lease uses bounded memory instead.
class HiveTransactionStorage
    implements TransactionStorage, ClosableTransactionStorage {
  /// Acquires the shared encrypted cache, opening it lazily on first use.
  factory HiveTransactionStorage({
    String boxName = defaultBoxName,
    TransactionHistoryCachePolicy policy =
        const TransactionHistoryCachePolicy(),
    HistoryCacheKeyProvider? keyProvider,
    CompactionStrategy? compactionStrategy,
    void Function(String message, Object error, StackTrace stackTrace)? onError,
  }) => HiveTransactionStorage.acquire(
    boxName: boxName,
    policy: policy,
    keyProvider: keyProvider,
    compactionStrategy: compactionStrategy,
    onError: onError,
  );

  HiveTransactionStorage._({
    required this.boxName,
    required this.policy,
    required HistoryCacheKeyProvider keyProvider,
    CompactionStrategy? compactionStrategy,
    void Function(String message, Object error, StackTrace stackTrace)? onError,
  }) : _keyProvider = keyProvider,
       _compactionStrategy = compactionStrategy ?? _defaultCompaction,
       _onError = onError ?? _logError,
       _retention = TransactionCacheRetention(policy);

  /// Acquires the single owner for [boxName]. Each caller must [close] once.
  factory HiveTransactionStorage.acquire({
    String boxName = defaultBoxName,
    TransactionHistoryCachePolicy policy =
        const TransactionHistoryCachePolicy(),
    HistoryCacheKeyProvider? keyProvider,
    CompactionStrategy? compactionStrategy,
    void Function(String message, Object error, StackTrace stackTrace)? onError,
  }) {
    final name = boxName.toLowerCase();
    final provider = keyProvider ?? _defaultKeyProvider;
    final existing = _acquired[name];
    if (existing != null) {
      if (existing.policy != policy ||
          !identical(existing._keyProvider, provider)) {
        throw ArgumentError(
          'Conflicting transaction history cache configuration',
        );
      }
      existing._acquireCount++;
      return existing;
    }
    final created = HiveTransactionStorage._(
      boxName: name,
      policy: policy,
      keyProvider: provider,
      compactionStrategy: compactionStrategy,
      onError: onError,
    );
    _acquired[name] = created;
    return created;
  }

  static final _defaultKeyProvider = SecureHistoryCacheKeyProvider();
  static final _acquired = <String, HiveTransactionStorage>{};
  static final _pendingClose = <String, Future<void>>{};

  /// Versioned encrypted cache, separate from the retired plaintext box.
  static const defaultBoxName = 'komodo_tx_history_v2';
  static const _plaintextBoxName = 'komodo_tx_history_v1';
  static const _deleteTimeout = Duration(seconds: 5);
  static const _openBatchSize = 64;

  /// Name of the encrypted Hive box.
  final String boxName;

  /// Limits shared by persistence and its memory fallback.
  final TransactionHistoryCachePolicy policy;
  final HistoryCacheKeyProvider _keyProvider;
  final CompactionStrategy _compactionStrategy;
  final void Function(String, Object, StackTrace) _onError;
  final _mutex = Mutex();
  final _index = TransactionOrderIndex();
  final TransactionCacheRetention _retention;
  final _sessionScopes = <String, AssetTransactionHistoryId>{};
  final _dirtyScopes = <String>{};

  LazyBox<String>? _box;
  Future<LazyBox<String>?>? _opening;
  InMemoryTransactionStorage? _fallback;
  HistoryCacheLease? _lease;
  HiveCipher? _cipher;
  Hmac? _keyHmac;
  int _acquireCount = 1;
  int _lastAccess = 0;

  /// Whether this owner serves bounded memory because persistence is
  /// unavailable.
  bool get isDegraded => _fallback != null;

  /// Logical retained bytes, including serialized metadata and index
  /// allowances.
  int get logicalBytes => _fallback?.logicalBytes ?? _retention.logicalBytes;

  int _accessNow() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return _lastAccess = now > _lastAccess ? now : _lastAccess + 1;
  }

  String _registerScope(WalletId walletId, AssetId assetId) {
    final scope = TransactionStorageKey.prefix(walletId, assetId);
    if (_index.count(scope) > 0) {
      _sessionScopes[scope] = AssetTransactionHistoryId(walletId, assetId);
      _retention.touch(scope, _accessNow());
      _dirtyScopes.add(scope);
    }
    return scope;
  }

  String _diskKey(String orderKey) {
    final parts = TransactionStorageKey.parse(orderKey)!;
    return _keyHmac!
        .convert(utf8.encode('${parts.prefix}${parts.idToken}'))
        .toString();
  }

  @override
  Future<void> storeTransaction(Transaction transaction, WalletId walletId) =>
      storeTransactions([transaction], walletId);

  @override
  Future<void> storeTransactions(
    List<Transaction> transactions,
    WalletId walletId,
  ) async {
    if (transactions.isEmpty) return;
    if (transactions.any((transaction) => transaction.internalId.isEmpty)) {
      throw TransactionStorageException(
        'Transaction internal ID cannot be empty',
      );
    }
    await _mutex.protect(() async {
      final box = await _ensureOpen();
      if (box == null) {
        return _fallback!.storeTransactions(transactions, walletId);
      }
      try {
        for (final group in groupBy(
          transactions,
          (Transaction tx) => tx.assetId,
        ).entries) {
          final batch = <String, Transaction>{};
          for (final row in group.value) {
            batch.update(
              row.internalId,
              (previous) =>
                  TransactionMergeUtils.mergeTransactionFields(previous, row),
              ifAbsent: () => row,
            );
          }
          await _writeBatch(box, walletId, group.key, batch.values);
        }
      } on Object catch (error, stack) {
        await _degrade(
          box,
          'Could not persist transaction history',
          error,
          stack,
        );
        await _fallback!.storeTransactions(transactions, walletId);
      }
    });
  }

  Future<void> _writeBatch(
    LazyBox<String> box,
    WalletId walletId,
    AssetId assetId,
    Iterable<Transaction> transactions,
  ) async {
    final scope = _registerScope(walletId, assetId);
    _sessionScopes[scope] = AssetTransactionHistoryId(walletId, assetId);
    final accessedAt = _accessNow();
    _retention.touch(scope, accessedAt);
    _dirtyScopes.add(scope);
    final writes = <String, _HistoryEnvelope>{};
    final incomingRows = transactions.toList(growable: false);
    final previousKeys = [
      for (final row in incomingRows)
        _index.keyForPrefixedId(scope, row.internalId),
    ];
    // Pipeline a page's IndexedDB reads rather than paying a round trip per
    // row.
    final previousRows = await Future.wait([
      for (final key in previousKeys)
        key == null
            ? Future<_HistoryEnvelope?>.value()
            : _readEnvelope(box, key),
    ]);
    for (var i = 0; i < incomingRows.length; i++) {
      final incoming = incomingRows[i];
      final previousKey = previousKeys[i];
      final previous = previousRows[i];
      final previousTransaction = previous == null
          ? null
          : await _decode(
              previous.record,
              previousKey!,
              scopedAssetId: assetId,
            );
      final merged = previousTransaction == null
          ? incoming
          : TransactionMergeUtils.mergeTransactionFields(
              previousTransaction,
              incoming,
            );
      final orderKey = TransactionStorageKey.build(
        prefix: scope,
        timestamp: merged.timestamp,
        internalId: merged.internalId,
      );
      final record = TransactionRecordCodec.encode(merged);
      final diskKey = _diskKey(orderKey);
      if (previous?.record == record && previous?.orderKey == orderKey) {
        continue;
      }
      final envelope = _HistoryEnvelope(orderKey, record, accessedAt);
      writes[diskKey] = envelope;
      _retention.put(diskKey, envelope.entry, accessedAt);
    }

    // Plan eviction before writing so even an oversized network page cannot
    // create an unbounded durable cache. A failed delete disables persistence.
    final evicted = _retention.prune();
    if (evicted.isNotEmpty) {
      await box.deleteAll(evicted);
      for (final key in evicted) {
        writes.remove(key);
      }
      _rebuildIndex();
    }
    if (writes.isNotEmpty) {
      await box.putAll(
        writes.map((key, envelope) => MapEntry(key, envelope.encode())),
      );
      for (final envelope in writes.values) {
        _index.insert(envelope.orderKey);
      }
    }
    _forgetEmptyScopes();
    if (evicted.isNotEmpty) await box.compact();
  }

  @override
  Future<CachedTransactionPage> getTransactions(
    AssetId assetId,
    WalletId walletId, {
    String? fromId,
    int? pageNumber,
    int limit = 10,
  }) async {
    return _mutex.protect(() async {
      final box = await _ensureOpen();
      if (box == null) {
        return _fallback!.getTransactions(
          assetId,
          walletId,
          fromId: fromId,
          pageNumber: pageNumber,
          limit: limit,
        );
      }
      final scope = _registerScope(walletId, assetId);
      final List<String> keys;
      try {
        keys = _index.page(
          scope,
          limit: limit,
          fromId: fromId,
          pageNumber: pageNumber,
        );
      } on TransactionOrderIndexCursorException {
        throw TransactionStorageException('Starting transaction not found');
      }
      final envelopes = await Future.wait(
        keys.map((key) => _readEnvelope(box, key)),
      );
      final transactions = <Transaction>[];
      for (var i = 0; i < keys.length; i++) {
        final envelope = envelopes[i];
        if (envelope == null) continue;
        final row = await _decode(
          envelope.record,
          keys[i],
          scopedAssetId: assetId,
        );
        if (row != null) transactions.add(row);
      }
      return CachedTransactionPage(
        transactions: transactions,
        cachedCount: _index.count(scope),
      );
    });
  }

  @override
  Future<Transaction?> getTransactionById(String internalId) async {
    return _mutex.protect(() async {
      final box = await _ensureOpen();
      if (box == null) return _fallback!.getTransactionById(internalId);
      final key = _index.keyForId(internalId);
      if (key == null) return null;
      final scope = TransactionStorageKey.parse(key)!.prefix;
      _retention.touch(scope, _accessNow());
      _dirtyScopes.add(scope);
      final envelope = await _readEnvelope(box, key);
      return envelope == null ? null : await _decode(envelope.record, key);
    });
  }

  @override
  Future<void> clearTransactions(AssetId assetId, WalletId walletId) async {
    await _mutex.protect(() async {
      final box = await _ensureOpen();
      if (box == null) return _fallback!.clearTransactions(assetId, walletId);
      await _removeScopes(box, [
        TransactionStorageKey.prefix(walletId, assetId),
      ]);
    });
  }

  /// Wallet deletion purges the cache, including its bounded memory fallback.
  Future<void> purgeWallet(WalletId walletId) async {
    await _mutex.protect(() async {
      final box = await _ensureOpen();
      if (box == null) {
        await _fallback!.purgeWallet(walletId);
        throw TransactionStorageException(
          'Persistent history could not be purged; memory was cleared',
        );
      }
      final prefix = TransactionStorageKey.walletPrefix(walletId);
      return _removeScopes(
        box,
        _index.prefixes.where((scope) => scope.startsWith(prefix)).toList(),
      );
    });
  }

  Future<void> _removeScopes(LazyBox<String> box, List<String> scopes) async {
    final keys = [for (final scope in scopes) ..._index.keysFor(scope)];
    try {
      await box.deleteAll(keys.map(_diskKey));
      for (final key in keys) {
        _forget(key);
      }
      _forgetEmptyScopes();
      if (keys.isNotEmpty) await box.compact();
    } on Object catch (error, stack) {
      _report('Could not purge transaction history', error, stack);
      throw TransactionStorageException(
        'Persistent history could not be purged',
      );
    }
  }

  @override
  Future<String?> getLatestTransactionId(
    AssetId assetId,
    WalletId walletId,
  ) async {
    return _mutex.protect(() async {
      final box = await _ensureOpen();
      if (box == null) {
        return _fallback!.getLatestTransactionId(assetId, walletId);
      }
      final scope = _registerScope(walletId, assetId);
      final key = _index.latestKey(scope);
      if (key == null) return null;
      final parts = TransactionStorageKey.parse(key)!;
      if (!parts.idTokenIsHashed) return parts.idToken;
      final envelope = await _readEnvelope(box, key);
      return envelope == null
          ? null
          : (await _decode(
              envelope.record,
              key,
              scopedAssetId: assetId,
            ))?.internalId;
    });
  }

  @override
  Future<StorageStats> getStats() async {
    return _mutex.protect(() async {
      final box = await _ensureOpen();
      if (box == null) return _fallback!.getStats();
      final perAsset = <AssetTransactionHistoryId, int>{};
      int? oldest;
      int? newest;
      for (final scope in _index.prefixes) {
        final stats = _index.statsFor(scope)!;
        final identity = _sessionScopes[scope];
        if (identity != null) perAsset[identity] = stats.count;
        if (oldest == null || stats.oldestMicros < oldest) {
          oldest = stats.oldestMicros;
        }
        if (newest == null || stats.newestMicros > newest) {
          newest = stats.newestMicros;
        }
      }
      if (oldest == null || newest == null) {
        throw TransactionStorageException('No transactions available');
      }
      return StorageStats(
        totalTransactions: _index.length,
        transactionsPerAsset: perAsset,
        oldestTransaction: DateTime.fromMicrosecondsSinceEpoch(
          oldest,
          isUtc: true,
        ),
        newestTransaction: DateTime.fromMicrosecondsSinceEpoch(
          newest,
          isUtc: true,
        ),
      );
    });
  }

  Future<_HistoryEnvelope?> _readEnvelope(
    LazyBox<String> box,
    String orderKey,
  ) async {
    try {
      final encoded = await box.get(_diskKey(orderKey));
      if (encoded != null) {
        final envelope = _HistoryEnvelope.decode(encoded);
        if (envelope.orderKey == orderKey) return envelope;
      }
    } on Object catch (error, stack) {
      _report('Could not read cached transaction', error, stack);
    }
    _forget(orderKey);
    await _evict(box, orderKey);
    return null;
  }

  Future<Transaction?> _decode(
    String record,
    String orderKey, {
    AssetId? scopedAssetId,
  }) async {
    try {
      return TransactionRecordCodec.decode(
        record,
        scopedAssetId: scopedAssetId,
      );
    } on Object catch (error, stack) {
      _report('Could not decode cached transaction', error, stack);
      _forget(orderKey);
      final box = _box;
      if (box != null) await _evict(box, orderKey);
      return null;
    }
  }

  Future<void> _evict(LazyBox<String> box, String orderKey) async {
    try {
      await box.delete(_diskKey(orderKey));
    } on Object {
      // The unreadable row is already excluded from the live index. Reopening
      // retries eviction before admitting any cached rows.
    }
  }

  void _forget(String orderKey) {
    _index.remove(orderKey);
    _retention.remove(_diskKey(orderKey));
  }

  void _forgetEmptyScopes() {
    final live = _index.prefixes.toSet();
    _sessionScopes.removeWhere((scope, _) => !live.contains(scope));
    _retention.scopeAccess.removeWhere((scope, _) => !live.contains(scope));
    _dirtyScopes.removeWhere((scope) => !live.contains(scope));
  }

  void _rebuildIndex() => _index.rebuildFromKeys(
    _retention.entries.values.map((entry) => entry.orderKey),
  );

  Future<LazyBox<String>?> _ensureOpen() {
    if (_acquireCount == 0) {
      return Future.error(StateError('Transaction history cache is closed'));
    }
    if (_box != null) return Future.value(_box);
    if (_fallback != null) return Future.value();
    return _opening ??= _open();
  }

  Future<LazyBox<String>?> _open() async {
    LazyBox<String>? opened;
    try {
      await _pendingClose[boxName];
      _lease = await HistoryCacheLease.acquire(boxName);
      // Retire plaintext even if key acquisition fails. No legacy record is
      // imported or copied to the encrypted cache.
      if (boxName == defaultBoxName) await retireLegacyCache();
      final key = await _keyProvider
          .loadOrCreate(boxName)
          .timeout(_deleteTimeout);
      if (key.length != 32 || key.any((byte) => byte < 0 || byte > 255)) {
        throw StateError('Transaction history cache key is invalid');
      }
      final master = Hmac(sha256, key);
      _cipher = HiveAesCipher(
        master.convert(utf8.encode('history-encryption-v2')).bytes,
      );
      _keyHmac = Hmac(
        sha256,
        master.convert(utf8.encode('history-identifiers-v2')).bytes,
      );
      if (Hive.isBoxOpen(boxName)) {
        // Hive silently returns an already-open box without checking its
        // cipher.
        // Only the SDK registry may share a handle; an external handle is
        // unsafe.
        throw StateError('Transaction history cache has an external owner');
      }
      try {
        opened = await _openBox();
      } on Object {
        await _deleteBox(boxName);
        opened = await _openBox();
      }
      _box = opened;
      await _rebuildFromEnvelopes(opened);
      return opened;
    } on Object catch (error, stack) {
      await _degrade(
        opened,
        'Encrypted transaction history is unavailable',
        error,
        stack,
      );
      return null;
    } finally {
      _opening = null;
    }
  }

  Future<LazyBox<String>> _openBox() => Hive.openLazyBox<String>(
    boxName,
    encryptionCipher: _cipher,
    compactionStrategy: _compactionStrategy,
    // A wrong key must not make Hive silently truncate an otherwise valid file.
    // Explicit cache recovery below deletes and rebuilds the whole cache.
    crashRecovery: false,
  );

  Future<void> _rebuildFromEnvelopes(LazyBox<String> box) async {
    _retention.clear();
    final keys = box.keys.toList(growable: false);
    var deleted = false;
    for (var start = 0; start < keys.length; start += _openBatchSize) {
      final batch = keys.skip(start).take(_openBatchSize).toList();
      final envelopes = await Future.wait(
        batch.map((key) async {
          try {
            if (key is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(key)) {
              return null;
            }
            final value = await box.get(key);
            if (value == null) return null;
            final envelope = _HistoryEnvelope.decode(value);
            if (_diskKey(envelope.orderKey) != key) return null;
            return envelope;
          } on Object {
            return null;
          }
        }),
      );
      final invalid = <dynamic>[];
      for (var i = 0; i < batch.length; i++) {
        final envelope = envelopes[i];
        if (envelope == null) {
          invalid.add(batch[i]);
          continue;
        }
        _retention.put(batch[i] as String, envelope.entry, envelope.accessedAt);
        if (envelope.accessedAt > _lastAccess) {
          _lastAccess = envelope.accessedAt;
        }
      }
      invalid.addAll(_retention.prune());
      if (invalid.isNotEmpty) {
        await box.deleteAll(invalid);
        deleted = true;
      }
    }
    _rebuildIndex();
    if (deleted) await box.compact();
  }

  /// Deletes the obsolete plaintext cache without reading or migrating rows.
  ///
  /// Bootstrap calls this even when persistence is disabled. A blocked browser
  /// delete has a deadline; failures are retried on subsequent cache opens and
  /// SDK starts, without touching any other Hive box or secure-storage key.
  static Future<void> retireLegacyCache() async {
    try {
      // Deleting a nonexistent box is safe. Hive's web boxExists opens an
      // IndexedDB connection without closing it, which would block our delete.
      await _deleteBox(_plaintextBoxName);
    } on Object {
      developer.log(
        'Could not retire legacy transaction cache; cleanup will retry',
        name: 'HiveTransactionStorage',
      );
    }
  }

  static Future<void> _deleteBox(String name) =>
      Hive.deleteBoxFromDisk(name).timeout(_deleteTimeout);

  Future<void> _degrade(
    LazyBox<String>? box,
    String message,
    Object error,
    StackTrace stack,
  ) async {
    _report(message, error, stack);
    _fallback ??= InMemoryTransactionStorage(policy: policy);
    _box = null;
    _retention.clear();
    _index.rebuildFromKeys(const []);
    _sessionScopes.clear();
    _dirtyScopes.clear();
    try {
      await box?.close();
    } on Object {
      // Cache faults cannot stop network history.
    }
    try {
      await _lease?.release();
    } on Object {
      // Releasing a failed cache must not break network history.
    }
    _lease = null;
    _cipher = null;
    _keyHmac = null;
  }

  /// Persists scope recency once per session instead of rewriting every read.
  Future<void> _flushAccesses(LazyBox<String> box) async {
    for (final scope in _dirtyScopes.toList()) {
      final orderKey = _index.latestKey(scope);
      final access = _retention.scopeAccess[scope];
      if (orderKey == null || access == null) continue;
      final envelope = await _readEnvelope(box, orderKey);
      if (envelope == null || envelope.accessedAt == access) continue;
      await box.put(
        _diskKey(orderKey),
        _HistoryEnvelope(orderKey, envelope.record, access).encode(),
      );
    }
    _dirtyScopes.clear();
  }

  @override
  Future<void> close() async {
    if (_acquireCount == 0) return;
    if (--_acquireCount > 0) return;
    _acquired.remove(boxName);
    final closing = () async {
      await _opening;
      await _mutex.protect(() async {
        final box = _box;
        _box = null;
        try {
          if (box != null) {
            await _flushAccesses(box);
            await box.compact();
          }
        } on Object catch (error, stack) {
          _report('Could not compact transaction history', error, stack);
        } finally {
          try {
            await box?.close();
          } on Object catch (error, stack) {
            _report('Could not close transaction history', error, stack);
          }
          try {
            await _lease?.release();
          } on Object catch (error, stack) {
            _report(
              'Could not release transaction cache ownership',
              error,
              stack,
            );
          }
          _lease = null;
          _cipher = null;
          _keyHmac = null;
          _retention.clear();
          _index.rebuildFromKeys(const []);
          _sessionScopes.clear();
          _dirtyScopes.clear();
        }
      });
    }();
    _pendingClose[boxName] = closing;
    await closing;
  }

  void _report(String message, Object error, StackTrace stack) => _onError(
    message,
    StateError('Transaction history cache operation failed'),
    stack,
  );

  static bool _defaultCompaction(int entries, int deleted) =>
      deleted > 60 && (deleted / entries > 0.15 || deleted > 20000);

  static void _logError(String message, Object error, StackTrace stack) {
    developer.log(message, name: 'HiveTransactionStorage');
  }
}

class _HistoryEnvelope {
  const _HistoryEnvelope(this.orderKey, this.record, this.accessedAt);

  factory _HistoryEnvelope.decode(String encoded) {
    try {
      final value = jsonDecode(encoded);
      if (value is Map<String, dynamic> &&
          value['v'] == 2 &&
          value['key'] is String &&
          value['record'] is String &&
          value['access'] is int &&
          (value['access'] as int) >= 0 &&
          TransactionStorageKey.parse(value['key'] as String) != null) {
        return _HistoryEnvelope(
          value['key'] as String,
          value['record'] as String,
          value['access'] as int,
        );
      }
    } on Object {
      // Never surface a JSON exception containing decrypted transaction data.
    }
    throw StateError('Invalid transaction history cache envelope');
  }
  final String orderKey;
  final String record;
  final int accessedAt;

  TransactionCacheEntry get entry => TransactionCacheEntry(
    scope: TransactionStorageKey.parse(orderKey)!.prefix,
    orderKey: orderKey,
    logicalBytes: TransactionCacheEntry.sizeOf(record, orderKey),
  );

  String encode() => jsonEncode({
    'v': 2,
    'key': orderKey,
    'record': record,
    'access': accessedAt,
  });
}
