import 'package:komodo_defi_sdk/src/transaction_history/transaction_storage_key.dart';

/// Aggregate counts and time bounds for one (wallet, asset) pair.
class TransactionPrefixStats {
  /// Creates stats for a prefix.
  const TransactionPrefixStats({
    required this.count,
    required this.oldestMicros,
    required this.newestMicros,
  });

  /// How many transactions are stored under the prefix.
  final int count;

  /// Microsecond timestamp of the oldest stored transaction.
  final int oldestMicros;

  /// Microsecond timestamp of the newest stored transaction.
  final int newestMicros;
}

/// In-memory ordering index over the persisted transaction keyspace.
///
/// Every answer this class gives is derived from the keys alone, so opening a
/// box and serving a page costs no value reads beyond the rows actually
/// returned. That is what makes a lazy box viable: the ordering field lives in
/// the key ([TransactionStorageKey]), so the index can be rebuilt from
/// `box.keys` without deserializing a single record.
///
/// Ordering matches `InMemoryTransactionStorage`: **timestamp descending, then
/// internal ID descending** as a stable tiebreaker. The index deliberately does
/// not rely on Hive's own key ordering - the comparator is ours, so the keys'
/// lexicographic order is irrelevant.
class TransactionOrderIndex {
  /// Ordered keys per `<walletToken>|<assetToken>|` prefix.
  final _orderedByPrefix = <String, List<String>>{};

  /// Position of each key within its prefix's ordered list.
  final _positionByKey = <String, int>{};

  /// `prefix -> internalId token -> key`.
  final _keyByPrefixedId = <String, Map<String, String>>{};

  /// `internalId token -> key`, across every prefix.
  ///
  /// Backs the unscoped [keyForId] lookup so it costs one map hit rather than
  /// a scan. Insertion order decides collisions, mirroring the in-memory
  /// implementation's "first matching asset wins".
  final _keyByGlobalId = <String, String>{};

  /// Every prefix currently holding at least one transaction.
  Iterable<String> get prefixes => _orderedByPrefix.keys;

  /// Total number of indexed transactions.
  int get length => _positionByKey.length;

  /// Whether nothing is indexed.
  bool get isEmpty => _positionByKey.isEmpty;

  /// Discards all state and rebuilds from [keys].
  ///
  /// Keys that do not parse are skipped and returned, so the caller can evict
  /// them from the box.
  List<String> rebuildFromKeys(Iterable<String> keys) {
    _orderedByPrefix.clear();
    _positionByKey.clear();
    _keyByPrefixedId.clear();
    _keyByGlobalId.clear();

    final unparseable = <String>[];
    final parsedByPrefix = <String, List<(String, TransactionKeyParts)>>{};

    for (final key in keys) {
      final parts = TransactionStorageKey.parse(key);
      if (parts == null) {
        unparseable.add(key);
        continue;
      }
      parsedByPrefix.putIfAbsent(parts.prefix, () => []).add((key, parts));
    }

    for (final entry in parsedByPrefix.entries) {
      final ordered = entry.value..sort((a, b) => _compareParts(a.$2, b.$2));
      final keyList = <String>[];
      final idMap = <String, String>{};
      for (final (key, parts) in ordered) {
        _positionByKey[key] = keyList.length;
        keyList.add(key);
        idMap[parts.idToken] = key;
        _keyByGlobalId.putIfAbsent(parts.idToken, () => key);
      }
      _orderedByPrefix[entry.key] = keyList;
      _keyByPrefixedId[entry.key] = idMap;
    }

    return unparseable;
  }

  /// Inserts [key] into the index, replacing any previous key for the same
  /// (prefix, internal ID) pair.
  ///
  /// Returns the replaced key when the transaction was re-keyed - which happens
  /// when a pending row gains a real timestamp - so the caller can delete the
  /// stale record.
  String? insert(String key) {
    final parts = TransactionStorageKey.parse(key);
    if (parts == null) return null;

    final previous = _keyByPrefixedId[parts.prefix]?[parts.idToken];
    if (previous == key) return null;
    if (previous != null) _removeParsed(previous);

    // Resolve the per-prefix maps only after the removal: dropping the last
    // entry for a prefix also drops the prefix's map, so a reference captured
    // beforehand would be written into a map no longer reachable from here.
    final ordered = _orderedByPrefix.putIfAbsent(parts.prefix, () => []);
    final position = _lowerBound(ordered, parts);
    ordered.insert(position, key);
    _reindexFrom(parts.prefix, position);
    _keyByPrefixedId.putIfAbsent(parts.prefix, () => {})[parts.idToken] = key;
    _keyByGlobalId[parts.idToken] = key;

    return previous;
  }

  /// Removes [key] from the index. Unknown keys are ignored.
  void remove(String key) => _removeParsed(key);

  /// Removes every key under [prefix].
  void removePrefix(String prefix) {
    final ordered = _orderedByPrefix.remove(prefix);
    if (ordered != null) {
      for (final key in ordered) {
        _positionByKey.remove(key);
      }
    }
    final idMap = _keyByPrefixedId.remove(prefix);
    if (idMap != null) {
      for (final entry in idMap.entries) {
        if (_keyByGlobalId[entry.key] == entry.value) {
          _keyByGlobalId.remove(entry.key);
          _restoreGlobalId(entry.key);
        }
      }
    }
  }

  /// Re-points the unscoped lookup at a surviving row for [idToken].
  ///
  /// The same internal ID can legitimately exist under more than one prefix, so
  /// dropping one must not make the others unreachable through [keyForId].
  void _restoreGlobalId(String idToken) {
    for (final entry in _keyByPrefixedId.entries) {
      final candidate = entry.value[idToken];
      if (candidate != null) {
        _keyByGlobalId[idToken] = candidate;
        return;
      }
    }
  }

  /// Removes every prefix starting with [walletPrefix].
  void removeWallet(String walletPrefix) {
    final matching = _orderedByPrefix.keys
        .where((prefix) => prefix.startsWith(walletPrefix))
        .toList();
    for (final prefix in matching) {
      removePrefix(prefix);
    }
  }

  /// All keys under [prefix], newest first.
  List<String> keysFor(String prefix) =>
      List.unmodifiable(_orderedByPrefix[prefix] ?? const []);

  /// How many transactions are stored under [prefix].
  int count(String prefix) => _orderedByPrefix[prefix]?.length ?? 0;

  /// The key for [internalId] under [prefix], or `null`.
  ///
  /// [internalId] is normalised through [TransactionStorageKey.idTokenFor]:
  /// the maps are keyed by the token parsed out of the Hive key, which for an
  /// overlong ID is its digest, not the ID itself.
  String? keyForPrefixedId(String prefix, String internalId) =>
      _keyByPrefixedId[prefix]?[TransactionStorageKey.idTokenFor(internalId)];

  /// The key for [internalId] anywhere in the index, or `null`.
  String? keyForId(String internalId) =>
      _keyByGlobalId[TransactionStorageKey.idTokenFor(internalId)];

  /// The newest transaction's key under [prefix], or `null`.
  String? latestKey(String prefix) => _orderedByPrefix[prefix]?.firstOrNull;

  /// Count and time bounds for [prefix], or `null` when it holds nothing.
  TransactionPrefixStats? statsFor(String prefix) {
    final ordered = _orderedByPrefix[prefix];
    if (ordered == null || ordered.isEmpty) return null;
    // Ordered newest-first, so the bounds are the two ends.
    final newest = TransactionStorageKey.parse(ordered.first)?.timestampMicros;
    final oldest = TransactionStorageKey.parse(ordered.last)?.timestampMicros;
    if (newest == null || oldest == null) return null;
    return TransactionPrefixStats(
      count: ordered.length,
      oldestMicros: oldest,
      newestMicros: newest,
    );
  }

  /// Returns the slice of [prefix] a page request selects.
  ///
  /// Mirrors `InMemoryTransactionStorage.getTransactions`: [fromId] is an
  /// exclusive cursor, [pageNumber] is a one-based offset of [limit]-sized
  /// pages, and the two are mutually exclusive with [fromId] winning.
  ///
  /// Throws [TransactionOrderIndexCursorException] when [fromId] is not
  /// present, matching the in-memory store's behaviour for an unknown cursor.
  List<String> page(
    String prefix, {
    required int limit,
    String? fromId,
    int? pageNumber,
  }) {
    final ordered = _orderedByPrefix[prefix];
    if (ordered == null || ordered.isEmpty) return const [];

    var start = 0;
    if (fromId != null) {
      final cursorKey =
          _keyByPrefixedId[prefix]?[TransactionStorageKey.idTokenFor(fromId)];
      final cursorPosition = cursorKey == null
          ? null
          : _positionByKey[cursorKey];
      if (cursorPosition == null) {
        throw TransactionOrderIndexCursorException(fromId);
      }
      start = cursorPosition + 1;
    } else if (pageNumber != null && pageNumber > 1) {
      start = (pageNumber - 1) * limit;
    }

    if (start >= ordered.length || limit <= 0) return const [];
    final end = (start + limit).clamp(start, ordered.length);
    return ordered.sublist(start, end);
  }

  void _removeParsed(String key) {
    final parts = TransactionStorageKey.parse(key);
    if (parts == null) return;

    final position = _positionByKey.remove(key);
    final ordered = _orderedByPrefix[parts.prefix];
    if (position != null && ordered != null) {
      ordered.removeAt(position);
      _reindexFrom(parts.prefix, position);
      if (ordered.isEmpty) _orderedByPrefix.remove(parts.prefix);
    }

    final idMap = _keyByPrefixedId[parts.prefix];
    if (idMap != null && idMap[parts.idToken] == key) {
      idMap.remove(parts.idToken);
      if (idMap.isEmpty) _keyByPrefixedId.remove(parts.prefix);
    }
    if (_keyByGlobalId[parts.idToken] == key) {
      _keyByGlobalId.remove(parts.idToken);
      _restoreGlobalId(parts.idToken);
    }
  }

  void _reindexFrom(String prefix, int position) {
    final ordered = _orderedByPrefix[prefix];
    if (ordered == null) return;
    for (var i = position; i < ordered.length; i++) {
      _positionByKey[ordered[i]] = i;
    }
  }

  int _lowerBound(List<String> ordered, TransactionKeyParts parts) {
    var low = 0;
    var high = ordered.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      final midParts = TransactionStorageKey.parse(ordered[mid]);
      // A malformed key cannot be ordered against; treat it as sorting last so
      // the insert still lands somewhere deterministic.
      final comparison = midParts == null ? 1 : _compareParts(midParts, parts);
      if (comparison < 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  /// Timestamp descending, then internal ID descending.
  static int _compareParts(TransactionKeyParts a, TransactionKeyParts b) {
    final byTimestamp = b.timestampMicros.compareTo(a.timestampMicros);
    if (byTimestamp != 0) return byTimestamp;
    return b.idToken.compareTo(a.idToken);
  }
}

/// Thrown when a pagination cursor is not present in the index.
class TransactionOrderIndexCursorException implements Exception {
  /// Creates a cursor failure for [fromId].
  TransactionOrderIndexCursorException(this.fromId);

  /// The cursor that could not be resolved.
  final String fromId;

  @override
  String toString() =>
      'TransactionOrderIndexCursorException: unknown cursor "$fromId"';
}
