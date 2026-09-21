import 'dart:convert';

import 'package:komodo_defi_sdk/src/transaction_history/transaction_history_cache_policy.dart';

/// Metadata shared by the persistent and memory caches' eviction policies.
class TransactionCacheEntry {
  /// Records the metadata needed to account for and evict a row.
  const TransactionCacheEntry({
    required this.scope,
    required this.orderKey,
    required this.logicalBytes,
  });

  /// Opaque wallet/asset namespace used only within the SDK.
  final String scope;

  /// In-memory timestamp and ID key; it must never be written in plaintext.
  final String orderKey;

  /// Encoded payload and index allowance charged to this row.
  final int logicalBytes;

  /// Encoded data and key bytes, plus a conservative per-row index allowance.
  ///
  /// The allowance includes the scope's LRU entry (even for one-row scopes),
  /// id and position maps, byte accounting, and the encrypted envelope fields.
  static int sizeOf(String record, String orderKey) =>
      utf8
          .encode(
            jsonEncode({
              'v': 2,
              'key': orderKey,
              'record': record,
              'access': 9007199254740991,
            }),
          )
          .length +
      utf8.encode(orderKey).length * 2 +
      512;
}

/// Bounded metadata; calls are serialized by the owning cache's mutex.
class TransactionCacheRetention {
  /// Validates the limits before admitting any cached rows.
  TransactionCacheRetention(this.policy) {
    policy.validate();
  }

  /// Finite limits enforced by [prune].
  final TransactionHistoryCachePolicy policy;

  /// Retained metadata keyed by opaque storage identity.
  final entries = <String, TransactionCacheEntry>{};

  /// Last known use of each retained wallet/asset scope.
  final scopeAccess = <String, int>{};

  /// Total logical size of retained entries.
  int logicalBytes = 0;

  /// Advances scope recency without changing its rows.
  void touch(String scope, int accessedAt) {
    final previous = scopeAccess[scope] ?? 0;
    if (accessedAt > previous) scopeAccess[scope] = accessedAt;
  }

  /// Adds or replaces a row and updates byte accounting.
  void put(String key, TransactionCacheEntry entry, int accessedAt) {
    final previous = entries[key];
    logicalBytes += entry.logicalBytes - (previous?.logicalBytes ?? 0);
    entries[key] = entry;
    touch(entry.scope, accessedAt);
  }

  /// Removes a row from byte accounting.
  void remove(String key) {
    final removed = entries.remove(key);
    if (removed == null) return;
    logicalBytes -= removed.logicalBytes;
  }

  /// Forgets all index and recency metadata.
  void clear() {
    entries.clear();
    scopeAccess.clear();
    logicalBytes = 0;
  }

  /// Removes older entries within scopes, then least recently used scopes.
  /// Returns opaque storage keys for the owner to delete from its backing
  /// store.
  List<String> prune() {
    final grouped = <String, List<String>>{};
    for (final item in entries.entries) {
      grouped.putIfAbsent(item.value.scope, () => []).add(item.key);
    }
    for (final keys in grouped.values) {
      keys.sort((a, b) => entries[a]!.orderKey.compareTo(entries[b]!.orderKey));
    }
    final removed = <String>[];
    void evict(String key) {
      remove(key);
      removed.add(key);
    }

    for (final keys in grouped.values) {
      final excess = keys.length - policy.maxTransactionsPerAsset;
      if (excess > 0) {
        for (final key in keys.take(excess)) {
          evict(key);
        }
        keys.removeRange(0, excess);
      }
    }

    final scopes = grouped.keys.toList()
      ..sort((a, b) {
        final byAccess = (scopeAccess[a] ?? 0).compareTo(scopeAccess[b] ?? 0);
        return byAccess != 0 ? byAccess : a.compareTo(b);
      });
    for (final scope in scopes) {
      for (final key in grouped[scope]!) {
        if (entries.length <= policy.maxTransactions &&
            logicalBytes <= policy.maxLogicalBytes) {
          break;
        }
        evict(key);
      }
    }
    final liveScopes = entries.values.map((entry) => entry.scope).toSet();
    scopeAccess.removeWhere((scope, _) => !liveScopes.contains(scope));
    return removed;
  }
}
