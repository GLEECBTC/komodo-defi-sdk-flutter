import 'dart:async';
import 'dart:developer' as developer;

import 'package:collection/collection.dart';
import 'package:hive_ce/hive.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_merge_utils.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_order_index.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_record_codec.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_storage.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_storage_key.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mutex/mutex.dart';

/// A [TransactionStorage] that can release its backing resources.
///
/// Deliberately separate from [TransactionStorage] so that adding it does not
/// break the hand-written fakes that `implements TransactionStorage`.
// ignore: one_member_abstracts
abstract interface class ClosableTransactionStorage {
  /// Flushes and releases the backing store.
  Future<void> close();
}

/// Transaction history persisted in a lazy Hive box.
///
/// ## Shape
///
/// One box entry per transaction, keyed by [TransactionStorageKey]. Ordering,
/// pagination, lookups and stats are served by [TransactionOrderIndex], which
/// is rebuilt from the box's keys at open. Values therefore stay on disk until
/// a row is actually returned: a cold open costs one pass over the key list and
/// zero record decodes, and `getLatestTransactionId` - polled per watched asset
/// every 30 seconds - costs neither.
///
/// A per-transaction entry rather than one blob per asset is what keeps writes
/// proportional to what changed. Production stores a page at a time and
/// re-stores page one on every confirmations refresh; against a per-asset blob
/// that would rewrite the entire history each time, and Hive's VM backend is an
/// append-only log, so every rewrite stays on disk until compaction.
///
/// ## Failure posture
///
/// Throw for caller bugs, degrade for I/O. Transaction history is fully
/// reconstructible from the network, so no storage fault should be able to
/// break the wallet:
///
/// * Validation errors - an empty internal ID, an unknown pagination cursor -
///   throw [TransactionStorageException], exactly as the in-memory store does.
/// * A box that will not open is deleted and reopened once; if that also fails
///   the instance falls back to an in-memory store for the rest of the process
///   and reports [isDegraded]. Construction and first use never throw.
/// * A record that will not decode is skipped and evicted, leaving the rest of
///   the asset's history readable. This per-record containment is why the box
///   is lazy: a non-lazy box decodes everything at open, so one bad frame would
///   take the whole dataset with it.
/// * A failed write is logged and swallowed. The caller already has the rows it
///   fetched; failing a *cache* write must not turn a successful network fetch
///   into a user-visible error.
class HiveTransactionStorage
    implements TransactionStorage, ClosableTransactionStorage {
  /// Creates a Hive-backed transaction store.
  ///
  /// The box is opened lazily on first use, so construction is cheap and does
  /// not require Hive to be initialised yet.
  ///
  /// [knownWalletNamespaces], when supplied, is consulted once per open to
  /// drop history belonging to wallets that no longer exist. It fails open: if
  /// it throws or returns nothing, no rows are removed.
  HiveTransactionStorage({
    this.boxName = defaultBoxName,
    Future<Set<String>> Function()? knownWalletNamespaces,
    CompactionStrategy? compactionStrategy,
    HiveCipher? cipher,
    void Function(String message, Object error, StackTrace stackTrace)? onError,
  }) : _knownWalletNamespaces = knownWalletNamespaces,
       _compactionStrategy = compactionStrategy ?? _defaultCompaction,
       _cipher = cipher,
       _onError = onError ?? _logError;

  /// Returns the live store for [boxName], creating it on first acquisition.
  ///
  /// Hive boxes are process-global, so two SDK containers each constructing
  /// their own store over the same (default) box name would adopt one
  /// underlying box while maintaining independent order indexes - writes
  /// through one invisible to the other - and either container's dispose
  /// would close the box underneath the survivor. Acquiring shares a single
  /// instance, so every acquirer sees one index and one owner, and [close]
  /// releases the box only when the last acquirer lets go.
  ///
  /// [knownWalletNamespaces] and the other tuning parameters take effect only
  /// on the call that creates the instance; later acquirers share the first
  /// caller's configuration. The plain constructor stays for standalone,
  /// single-owner use (tests, custom wiring) and does not consult this
  /// registry.
  factory HiveTransactionStorage.acquire({
    String boxName = defaultBoxName,
    Future<Set<String>> Function()? knownWalletNamespaces,
    CompactionStrategy? compactionStrategy,
    HiveCipher? cipher,
    void Function(String message, Object error, StackTrace stackTrace)? onError,
  }) {
    final existing = _acquired[boxName];
    if (existing != null) {
      existing._acquireCount++;
      return existing;
    }
    final created = HiveTransactionStorage(
      boxName: boxName,
      knownWalletNamespaces: knownWalletNamespaces,
      compactionStrategy: compactionStrategy,
      cipher: cipher,
      onError: onError,
    ).._acquireCount = 1;
    _acquired[boxName] = created;
    return created;
  }

  /// Live [acquire]d instances by box name.
  static final Map<String, HiveTransactionStorage> _acquired = {};

  /// How many [acquire] calls this instance must outlive; 0 for instances
  /// built directly, whose [close] always really closes.
  int _acquireCount = 0;

  /// Box name for the current key layout.
  ///
  /// The version suffix tracks the *key* scheme; the record schema is versioned
  /// separately inside each value. Earlier layouts are deleted on first open so
  /// a bump does not orphan a full copy of the history on disk forever.
  static const String defaultBoxName = 'komodo_tx_history_v1';

  /// Box names from superseded key layouts, deleted on first successful open.
  static const List<String> _supersededBoxNames = <String>[];

  /// How long to wait for a recovery delete before giving up.
  ///
  /// On web `deleteBoxFromDisk` calls `IDBFactory.deleteDatabase`, which blocks
  /// while another tab holds the database open and never completes. Without a
  /// deadline, corruption recovery would hang the caller forever.
  static const Duration _deleteTimeout = Duration(seconds: 5);

  /// Name of the Hive box this instance reads and writes.
  final String boxName;

  final Future<Set<String>> Function()? _knownWalletNamespaces;
  final CompactionStrategy _compactionStrategy;
  final HiveCipher? _cipher;
  final void Function(String, Object, StackTrace) _onError;

  final _mutex = Mutex();
  final _index = TransactionOrderIndex();

  /// Live asset identities seen this session, keyed by asset token.
  ///
  /// Lets [getStats] name the (wallet, asset) pairs it reports without storing
  /// wallet names on disk - the wallet storage namespace is a one-way hash, so
  /// the alternative would be persisting wallet identity in the clear for a
  /// method with no production callers.
  final _sessionScopes = <String, AssetTransactionHistoryId>{};

  LazyBox<String>? _box;
  Future<LazyBox<String>?>? _opening;
  InMemoryTransactionStorage? _fallback;

  /// Whether the box is unusable and reads and writes are being served from
  /// memory only.
  bool get isDegraded => _fallback != null;

  @override
  Future<void> storeTransaction(Transaction transaction, WalletId walletId) =>
      storeTransactions([transaction], walletId);

  @override
  Future<void> storeTransactions(
    List<Transaction> transactions,
    WalletId walletId,
  ) async {
    if (transactions.isEmpty) return;
    for (final transaction in transactions) {
      if (transaction.internalId.isEmpty) {
        throw TransactionStorageException(
          'Transaction internal ID cannot be empty',
        );
      }
    }

    final box = await _ensureOpen();
    if (box == null) {
      return _fallback!.storeTransactions(transactions, walletId);
    }

    await _mutex.protect(() async {
      final grouped = groupBy(transactions, (Transaction tx) => tx.assetId);
      for (final entry in grouped.entries) {
        // Collapse duplicates within the batch first, so two perspectives of
        // one transfer arriving on the same page merge rather than overwrite.
        final batch = <String, Transaction>{};
        for (final transaction in entry.value) {
          batch.update(
            transaction.internalId,
            (existing) => TransactionMergeUtils.mergeTransactionFields(
              existing,
              transaction,
            ),
            ifAbsent: () => transaction,
          );
        }
        await _writeBatch(box, walletId, entry.key, batch.values);
      }
    });
  }

  Future<void> _writeBatch(
    LazyBox<String> box,
    WalletId walletId,
    AssetId assetId,
    Iterable<Transaction> transactions,
  ) async {
    final prefix = _registerScope(walletId, assetId);
    final writes = <String, String>{};

    // Resolve and read every row this batch will merge into up front, rather
    // than one await at a time inside the loop. The confirmations refresh
    // re-stores a full page every 30 seconds per watched asset, and on web
    // each read is its own IndexedDB round trip.
    final existingKeys = <String, String>{};
    for (final incoming in transactions) {
      final key = _index.keyForPrefixedId(prefix, incoming.internalId);
      if (key != null) existingKeys[incoming.internalId] = key;
    }
    final existingRecords = await _readRecords(box, existingKeys);

    for (final incoming in transactions) {
      final existingKey = existingKeys[incoming.internalId];
      final existingRecord = existingRecords[incoming.internalId];
      var merged = incoming;

      if (existingKey != null && existingRecord != null) {
        final existing = _decode(
          existingRecord,
          existingKey,
          scopedAssetId: assetId,
        );
        if (existing != null) {
          merged = TransactionMergeUtils.mergeTransactionFields(
            existing,
            incoming,
          );
        }
      }

      final encoded = TransactionRecordCodec.encode(merged);
      final key = TransactionStorageKey.build(
        prefix: prefix,
        timestamp: merged.timestamp,
        internalId: merged.internalId,
      );

      // Skip byte-identical rewrites. The confirmations refresh re-stores page
      // one every 30 seconds per watched asset, and most of those rows have not
      // changed at all.
      if (key == existingKey && encoded == existingRecord) continue;

      writes[key] = encoded;
    }

    if (writes.isEmpty) return;

    try {
      await box.putAll(writes);
    } on Object catch (error, stackTrace) {
      // The rows are already with the caller; a cache write failing must not
      // surface as a fetch failure. The index is deliberately untouched at
      // this point: rows Hive refused must not become authoritative, or the
      // store starts counting phantom records and reporting a latest
      // transaction ID that was never written.
      _onError(
        'failed to persist ${writes.length} transactions',
        error,
        stackTrace,
      );
      return;
    }

    // Index the rows only now that Hive actually holds them.
    final staleKeys = <String>[];
    for (final key in writes.keys) {
      // Re-keying (a pending row gaining a real timestamp) indexes the new
      // key first and deletes the old record after. A crash in between leaves
      // a duplicate that `rebuildFromKeys` collapses on the next open; the
      // reverse order would lose the row.
      final displaced = _index.insert(key);
      if (displaced != null && displaced != key) staleKeys.add(displaced);
    }

    if (staleKeys.isEmpty) return;

    try {
      await box.deleteAll(staleKeys);
    } on Object catch (error, stackTrace) {
      // The replacement rows are stored and indexed; a displaced record that
      // will not delete is unreachable through the index and merely wastes
      // its bytes until the box is next compacted or collected.
      _onError(
        'failed to delete ${staleKeys.length} displaced records',
        error,
        stackTrace,
      );
    }
  }

  @override
  Future<TransactionPage> getTransactions(
    AssetId assetId,
    WalletId walletId, {
    String? fromId,
    int? pageNumber,
    int limit = 10,
  }) async {
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

    return _mutex.protect(() async {
      final prefix = _registerScope(walletId, assetId);
      final total = _index.count(prefix);
      if (total == 0) {
        return TransactionPage(
          transactions: const [],
          total: 0,
          currentPage: pageNumber ?? 1,
          totalPages: 0,
        );
      }

      final List<String> keys;
      try {
        keys = _index.page(
          prefix,
          limit: limit,
          fromId: fromId,
          pageNumber: pageNumber,
        );
      } on TransactionOrderIndexCursorException {
        throw TransactionStorageException('Starting transaction not found');
      }

      final transactions = await _readAll(box, keys, scopedAssetId: assetId);
      return TransactionPage(
        transactions: transactions,
        total: total,
        nextPageId: transactions.lastOrNull?.internalId,
        currentPage: pageNumber ?? 1,
        totalPages: (total / limit).ceil(),
      );
    });
  }

  @override
  Future<Transaction?> getTransactionById(String internalId) async {
    final box = await _ensureOpen();
    if (box == null) return _fallback!.getTransactionById(internalId);

    return _mutex.protect(() async {
      final key = _index.keyForId(internalId);
      if (key == null) return null;
      final record = await _readRecord(box, key);
      if (record == null) return null;
      return _decode(record, key);
    });
  }

  @override
  Future<void> clearTransactions(AssetId assetId, WalletId walletId) async {
    final box = await _ensureOpen();
    if (box == null) return _fallback!.clearTransactions(assetId, walletId);

    await _mutex.protect(() async {
      final prefix = TransactionStorageKey.prefix(walletId, assetId);
      final keys = _index.keysFor(prefix);
      _index.removePrefix(prefix);
      if (keys.isEmpty) return;
      try {
        await box.deleteAll(keys);
      } on Object catch (error, stackTrace) {
        _onError('failed to clear ${assetId.id}', error, stackTrace);
      }
    });
  }

  @override
  Future<String?> getLatestTransactionId(
    AssetId assetId,
    WalletId walletId,
  ) async {
    final box = await _ensureOpen();
    if (box == null) {
      return _fallback!.getLatestTransactionId(assetId, walletId);
    }

    return _mutex.protect(() async {
      final prefix = _registerScope(walletId, assetId);
      final key = _index.latestKey(prefix);
      if (key == null) return null;
      final parts = TransactionStorageKey.parse(key);
      // The key holds a digest rather than the ID when the ID was over budget,
      // so fall back to the record in that case.
      if (parts != null && !parts.idTokenIsHashed) return parts.idToken;
      final record = await _readRecord(box, key);
      if (record == null) return null;
      return _decode(record, key, scopedAssetId: assetId)?.internalId;
    });
  }

  @override
  Future<StorageStats> getStats() async {
    final box = await _ensureOpen();
    if (box == null) return _fallback!.getStats();

    return _mutex.protect(() async {
      final perAsset = <AssetTransactionHistoryId, int>{};
      var total = 0;
      int? oldest;
      int? newest;

      for (final prefix in _index.prefixes.toList()) {
        final scope = _sessionScopes[prefix];
        // Only pairs this process has touched can be named: the wallet half of
        // a key is a one-way hash.
        if (scope == null) continue;
        final stats = _index.statsFor(prefix);
        if (stats == null) continue;
        perAsset[scope] = stats.count;
        total += stats.count;
        oldest = oldest == null
            ? stats.oldestMicros
            : (stats.oldestMicros < oldest ? stats.oldestMicros : oldest);
        newest = newest == null
            ? stats.newestMicros
            : (stats.newestMicros > newest ? stats.newestMicros : newest);
      }

      if (total == 0 || oldest == null || newest == null) {
        throw TransactionStorageException('No transactions available');
      }

      return StorageStats(
        totalTransactions: total,
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

  /// Deletes every stored transaction belonging to [walletId].
  ///
  /// Not wired into wallet deletion yet - no SDK-wide purge hook exists - but
  /// available to callers that delete a wallet, and used by [_collectGarbage].
  Future<void> purgeWallet(WalletId walletId) async {
    final box = await _ensureOpen();
    if (box == null) return;
    await _mutex.protect(
      () =>
          _purgeWalletPrefix(box, TransactionStorageKey.walletPrefix(walletId)),
    );
  }

  @override
  Future<void> close() async {
    // A shared instance closes only with its last acquirer; earlier releases
    // must not shut the box underneath the containers still using it.
    if (_acquireCount > 1) {
      _acquireCount--;
      return;
    }
    if (_acquireCount == 1) {
      _acquireCount = 0;
      _acquired.remove(boxName);
    }
    final closing = _mutex.protect(() async {
      final box = _box;
      _box = null;
      _opening = null;
      if (box == null) return;
      try {
        // A no-op on web, where the backend reports no compaction support.
        await box.compact();
        await box.close();
      } on Object catch (error, stackTrace) {
        _onError('failed to close $boxName', error, stackTrace);
      }
    });
    // Recorded before the first await: the registry entry is already gone, so
    // a concurrent acquire builds a fresh instance - whose open must wait for
    // this handle to actually release the box rather than adopt a still-open
    // box that is about to be closed underneath it. Never rejects; the close
    // body contains its own failures.
    _pendingCloseByBoxName[boxName] = closing;
    await closing;
  }

  /// The most recent in-flight (or completed) real close per box name; the
  /// next open of that box awaits it. See [close] and [_openBoxWithRecovery].
  static final Map<String, Future<void>> _pendingCloseByBoxName = {};

  Future<void> _purgeWalletPrefix(
    LazyBox<String> box,
    String walletPrefix,
  ) async {
    final keys = [
      for (final prefix in _index.prefixes.toList())
        if (prefix.startsWith(walletPrefix)) ..._index.keysFor(prefix),
    ];
    _index.removeWallet(walletPrefix);
    _sessionScopes.removeWhere((prefix, _) => prefix.startsWith(walletPrefix));
    if (keys.isEmpty) return;
    try {
      await box.deleteAll(keys);
    } on Object catch (error, stackTrace) {
      _onError('failed to purge a wallet', error, stackTrace);
    }
  }

  String _registerScope(WalletId walletId, AssetId assetId) {
    final prefix = TransactionStorageKey.prefix(walletId, assetId);
    _sessionScopes[prefix] = AssetTransactionHistoryId(walletId, assetId);
    return prefix;
  }

  /// Reads [keys] concurrently, preserving their order.
  ///
  /// One `await` per row put a page's worth of round trips on the path that
  /// paints the asset details list. That is invisible on the VM, where a read
  /// is a file offset, and very visible on web, where every `LazyBox.get` is
  /// its own IndexedDB transaction. Issuing them together lets the backend
  /// pipeline them, so a page costs one round trip's latency rather than N.
  ///
  /// [_readRecord] contains its own failures, so a single unreadable row still
  /// yields `null` here instead of failing the whole page.
  Future<List<Transaction>> _readAll(
    LazyBox<String> box,
    List<String> keys, {
    AssetId? scopedAssetId,
  }) async {
    if (keys.isEmpty) return const [];
    final records = await Future.wait(
      keys.map((key) => _readRecord(box, key)),
    );

    final transactions = <Transaction>[];
    for (var i = 0; i < keys.length; i++) {
      final record = records[i];
      if (record == null) continue;
      final transaction = _decode(
        record,
        keys[i],
        scopedAssetId: scopedAssetId,
      );
      if (transaction != null) transactions.add(transaction);
    }
    return transactions;
  }

  /// Reads the records behind [keysById] concurrently, keyed by the same ids.
  Future<Map<String, String>> _readRecords(
    LazyBox<String> box,
    Map<String, String> keysById,
  ) async {
    if (keysById.isEmpty) return const {};
    final ids = keysById.keys.toList();
    final records = await Future.wait(
      ids.map((id) => _readRecord(box, keysById[id]!)),
    );
    return {
      for (var i = 0; i < ids.length; i++)
        if (records[i] != null) ids[i]: records[i]!,
    };
  }

  Future<String?> _readRecord(LazyBox<String> box, String key) async {
    try {
      return await box.get(key);
    } on Object catch (error, stackTrace) {
      _onError('failed to read a stored transaction', error, stackTrace);
      // Out of the index first, like the decode-failure path: a key left
      // behind is a phantom the process keeps counting - short pages, wrong
      // totals, a latestKey that reads as null - while the eviction below is
      // only best-effort.
      _index.remove(key);
      unawaited(_evict(box, key));
      return null;
    }
  }

  /// Decodes one record, evicting it if it is unreadable.
  ///
  /// A record from a newer schema, or one that has been corrupted, costs a
  /// refetch rather than an error: dropping it keeps the rest of the asset's
  /// history usable.
  Transaction? _decode(String record, String key, {AssetId? scopedAssetId}) {
    try {
      return TransactionRecordCodec.decode(
        record,
        scopedAssetId: scopedAssetId,
      );
    } on TransactionRecordVersionException catch (error, stackTrace) {
      _onError('dropping a record from a newer schema', error, stackTrace);
    } on TransactionRecordFormatException catch (error, stackTrace) {
      _onError('dropping an unreadable record', error, stackTrace);
    }
    _index.remove(key);
    final box = _box;
    if (box != null) unawaited(_evict(box, key));
    return null;
  }

  Future<void> _evict(LazyBox<String> box, String key) async {
    try {
      await box.delete(key);
    } on Object catch (_) {
      // Best effort: the record is already out of the index.
    }
  }

  Future<LazyBox<String>?> _ensureOpen() {
    final box = _box;
    if (box != null) return Future.value(box);
    if (_fallback != null) return Future.value();
    return _opening ??= _open();
  }

  Future<LazyBox<String>?> _open() async {
    try {
      final box = await _openBoxWithRecovery();
      _box = box;
      // Unparseable keys, plus the stale halves of any re-key that crashed
      // between writing the replacement and deleting the displaced record.
      final dropped = _index.rebuildFromKeys(box.keys.whereType<String>());
      if (dropped.isNotEmpty) {
        _onError(
          'dropping ${dropped.length} unparseable or superseded keys',
          StateError('unindexable keys in $boxName'),
          StackTrace.current,
        );
        await box.deleteAll(dropped);
      }
      await _deleteSupersededBoxes();
      await _collectGarbage(box);
      return box;
    } on Object catch (error, stackTrace) {
      // Last resort: serve from memory so a broken cache cannot break history.
      _onError(
        'falling back to in-memory transaction storage',
        error,
        stackTrace,
      );
      _fallback = InMemoryTransactionStorage();
      _box = null;
      return null;
    } finally {
      _opening = null;
    }
  }

  Future<LazyBox<String>> _openBoxWithRecovery() async {
    // Wait out any final close of this box still in flight. Without this, an
    // instance acquired while the previous one was closing could adopt the
    // still-open box through `isBoxOpen` and then have it closed underneath
    // it, leaving a live store holding a dead box.
    final pendingClose = _pendingCloseByBoxName[boxName];
    if (pendingClose != null) await pendingClose;
    if (Hive.isBoxOpen(boxName)) return Hive.lazyBox<String>(boxName);
    try {
      return await _openBox();
    } on Object catch (error, stackTrace) {
      _onError('recovering an unreadable $boxName', error, stackTrace);
      await _deleteBox(boxName);
      return _openBox();
    }
  }

  Future<LazyBox<String>> _openBox() => Hive.openLazyBox<String>(
    boxName,
    encryptionCipher: _cipher,
    compactionStrategy: _compactionStrategy,
  );

  Future<void> _deleteBox(String name) async {
    // See [_deleteTimeout]: on web this can block indefinitely behind another
    // tab's open connection.
    await Hive.deleteBoxFromDisk(name).timeout(_deleteTimeout);
  }

  Future<void> _deleteSupersededBoxes() async {
    for (final name in _supersededBoxNames) {
      try {
        if (await Hive.boxExists(name)) await _deleteBox(name);
      } on Object catch (error, stackTrace) {
        _onError('failed to delete superseded box $name', error, stackTrace);
      }
    }
  }

  /// Drops history for wallets that no longer exist.
  ///
  /// Fails open in every uncertain case - a throwing or empty provider means
  /// "do not know", never "delete everything".
  Future<void> _collectGarbage(LazyBox<String> box) async {
    final provider = _knownWalletNamespaces;
    if (provider == null) return;

    final Set<String> known;
    try {
      known = await provider();
    } on Object catch (error, stackTrace) {
      _onError('skipping wallet GC: could not list wallets', error, stackTrace);
      return;
    }
    if (known.isEmpty) return;

    final knownTokens = known
        .map(TransactionStorageKey.tokenForNamespace)
        .toSet();
    final orphaned = <String>{
      for (final prefix in _index.prefixes)
        if (!knownTokens.contains(
          prefix.split(TransactionStorageKey.separator).first,
        ))
          prefix,
    };

    for (final prefix in orphaned) {
      await _purgeWalletPrefix(
        box,
        prefix.substring(0, TransactionStorageKey.tokenLength + 1),
      );
    }
  }

  static bool _defaultCompaction(int entries, int deletedEntries) =>
      deletedEntries > 60 &&
      (deletedEntries / entries > 0.15 || deletedEntries > 20000);

  static void _logError(String message, Object error, StackTrace stackTrace) {
    developer.log(
      message,
      name: 'HiveTransactionStorage',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
