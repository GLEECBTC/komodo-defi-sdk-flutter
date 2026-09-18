import 'package:meta/meta.dart';

/// Limits for reconstructible transaction history on disk or in memory.
///
/// These limits never apply to the unresolved-transfer journal. Older history
/// remains available through the provider even when it is no longer cached.
@immutable
class TransactionHistoryCachePolicy {
  /// Uses finite defaults suitable for a reconstructed transaction cache.
  const TransactionHistoryCachePolicy({
    this.maxTransactionsPerAsset = 1000,
    this.maxTransactions = 20000,
    this.maxLogicalBytes = 64 * 1024 * 1024,
  }) : assert(
         maxTransactionsPerAsset > 0,
         'Per-asset cache limit must be positive',
       ),
       assert(maxTransactions > 0, 'Global cache limit must be positive'),
       assert(maxLogicalBytes > 0, 'Cache byte limit must be positive');

  /// Maximum rows per wallet and asset, retaining newer transactions first.
  final int maxTransactionsPerAsset;

  /// Maximum rows across every wallet and asset in this cache.
  final int maxTransactions;

  /// Maximum logical bytes, including encoded rows, keys and index allowances.
  ///
  /// This is not a Dart heap or filesystem quota. Hive's append-only file is
  /// compacted after eviction and on close to reclaim superseded records.
  final int maxLogicalBytes;

  /// Rejects invalid limits in release builds as well as debug builds.
  void validate() {
    if (maxTransactionsPerAsset <= 0 ||
        maxTransactions <= 0 ||
        maxLogicalBytes <= 0) {
      throw ArgumentError('Transaction history cache limits must be positive');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TransactionHistoryCachePolicy &&
      maxTransactionsPerAsset == other.maxTransactionsPerAsset &&
      maxTransactions == other.maxTransactions &&
      maxLogicalBytes == other.maxLogicalBytes;

  @override
  int get hashCode =>
      Object.hash(maxTransactionsPerAsset, maxTransactions, maxLogicalBytes);
}
