import 'package:collection/collection.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Shared helpers for reconciling transaction lifecycle updates in clients.
///
/// This utility keeps identity stable by internal transaction ID while still
/// supporting a Tendermint-specific pending->confirmed bridge when a matching
/// event is re-emitted with a different internal ID.
class TransactionMergeUtils {
  TransactionMergeUtils._();

  static const ListEquality<String> _listEquality = ListEquality<String>();

  /// Canonical lifecycle key for transaction list reconciliation.
  static String transactionKey(Transaction transaction) {
    return transaction.internalId;
  }

  /// Merge commonly-updated fields from [incoming] into [existing].
  static Transaction mergeTransactionFields(
    Transaction existing,
    Transaction incoming,
  ) {
    return existing.copyWith(
      confirmations: incoming.confirmations,
      blockHeight: incoming.blockHeight,
      fee: incoming.fee ?? existing.fee,
      memo: incoming.memo ?? existing.memo,
      timestamp: incoming.timestamp,
    );
  }

  static bool isTendermintAsset(AssetId assetId) {
    return assetId.subClass == CoinSubClass.tendermint ||
        assetId.subClass == CoinSubClass.tendermintToken;
  }

  static bool isConfirmed(Transaction transaction) {
    return transaction.confirmations > 0 || transaction.blockHeight > 0;
  }

  static bool isPending(Transaction transaction) {
    return transaction.confirmations <= 0 && transaction.blockHeight == 0;
  }

  static bool matchesTransferFingerprint(
    Transaction first,
    Transaction second,
  ) {
    return _listEquality.equals(first.from, second.from) &&
        _listEquality.equals(first.to, second.to) &&
        first.balanceChanges.netChange == second.balanceChanges.netChange &&
        first.balanceChanges.totalAmount == second.balanceChanges.totalAmount;
  }

  /// Finds a pending transaction key that should be replaced by [incoming].
  ///
  /// This bridge is intentionally limited to Tendermint/TendermintToken assets
  /// with exactly one fingerprint match to avoid collapsing distinct transfers
  /// that share the same hash.
  static String? findPendingReplacementKey({
    required Map<String, Transaction> byKey,
    required Transaction incoming,
  }) {
    if (!isTendermintAsset(incoming.assetId) || !isConfirmed(incoming)) {
      return null;
    }

    final txHash = incoming.txHash;
    if (txHash == null || txHash.isEmpty) {
      return null;
    }

    final matchingEntries = byKey.entries.where((entry) {
      final existing = entry.value;
      return existing.assetId.isSameAsset(incoming.assetId) &&
          isPending(existing) &&
          existing.txHash == txHash &&
          matchesTransferFingerprint(existing, incoming);
    }).toList();

    if (matchingEntries.length != 1) {
      return null;
    }

    return matchingEntries.first.key;
  }
}

/// Stateful reconciler for merging transaction update batches into a list view.
class TransactionListReconciler {
  final Map<String, DateTime> _firstSeenAtByInternalId = <String, DateTime>{};

  /// Clears internal ordering state.
  void reset() => _firstSeenAtByInternalId.clear();

  /// Merges [incoming] updates into [existing] and returns sorted results.
  List<Transaction> merge({
    required List<Transaction> existing,
    required Iterable<Transaction> incoming,
  }) {
    final byKey = <String, Transaction>{
      for (final tx in existing) TransactionMergeUtils.transactionKey(tx): tx,
    };

    for (final tx in incoming) {
      _firstSeenAtByInternalId.putIfAbsent(
        tx.internalId,
        () => tx.timestamp.millisecondsSinceEpoch != 0
            ? tx.timestamp
            : DateTime.now(),
      );
      _mergeInPlace(byKey, tx);
    }

    final merged = byKey.values.toList()..sort(_compareTransactions);
    return merged;
  }

  void _mergeInPlace(Map<String, Transaction> byKey, Transaction incoming) {
    final incomingKey = TransactionMergeUtils.transactionKey(incoming);
    final existing = byKey[incomingKey];

    if (existing != null) {
      byKey[incomingKey] = TransactionMergeUtils.mergeTransactionFields(
        existing,
        incoming,
      );
      return;
    }

    final pendingReplacementKey =
        TransactionMergeUtils.findPendingReplacementKey(
          byKey: byKey,
          incoming: incoming,
        );

    if (pendingReplacementKey != null) {
      final pending = byKey.remove(pendingReplacementKey);
      if (pending != null) {
        final mergedPending = TransactionMergeUtils.mergeTransactionFields(
          pending,
          incoming,
        ).copyWith(internalId: incoming.internalId);

        final pendingFirstSeen = _firstSeenAtByInternalId.remove(
          pendingReplacementKey,
        );
        if (pendingFirstSeen != null) {
          _firstSeenAtByInternalId.putIfAbsent(
            incoming.internalId,
            () => pendingFirstSeen,
          );
        }

        byKey[incomingKey] = mergedPending;
        return;
      }
    }

    byKey[incomingKey] = incoming;
  }

  int _compareTransactions(Transaction left, Transaction right) {
    final unconfirmedTimestamp = DateTime.fromMillisecondsSinceEpoch(0);
    final leftIsUnconfirmed = left.timestamp == unconfirmedTimestamp;
    final rightIsUnconfirmed = right.timestamp == unconfirmedTimestamp;

    if (leftIsUnconfirmed && rightIsUnconfirmed) {
      final leftFirstSeen =
          _firstSeenAtByInternalId[left.internalId] ?? unconfirmedTimestamp;
      final rightFirstSeen =
          _firstSeenAtByInternalId[right.internalId] ?? unconfirmedTimestamp;
      final compareByFirstSeen = rightFirstSeen.compareTo(leftFirstSeen);
      if (compareByFirstSeen != 0) {
        return compareByFirstSeen;
      }
      return right.internalId.compareTo(left.internalId);
    }

    if (leftIsUnconfirmed) {
      return -1;
    }

    if (rightIsUnconfirmed) {
      return 1;
    }

    return right.timestamp.compareTo(left.timestamp);
  }
}
