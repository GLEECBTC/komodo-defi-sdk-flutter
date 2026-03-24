import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Base interface for transaction history strategies

abstract class TransactionHistoryStrategy {
  const TransactionHistoryStrategy();

  /// Get supported pagination modes for this strategy
  Set<Type> get supportedPaginationModes;

  /// Fetch transaction history with the specified pagination mode
  Future<MyTxHistoryResponse> fetchTransactionHistory(
    ApiClient client,
    Asset asset,
    TransactionPagination pagination,
  );

  /// Whether this strategy supports the given asset
  bool supportsAsset(Asset asset);

  /// Whether this strategy requires KDF transaction history to be enabled
  /// during activation for real-time updates and pagination to work.
  ///
  /// Default is true; strategies that source history externally
  /// (e.g. Etherscan)
  /// can override to false so activation can skip setting `tx_history` when
  /// streaming is also unsupported for the asset.
  bool requiresKdfTransactionHistory(Asset asset) => true;

  /// Whether `TransactionBasedPagination.fromId` is an opaque cursor that must
  /// come from a previous strategy response, rather than a stored transaction
  /// ID from local history.
  ///
  /// Managers can use this to avoid seeding resume flows with transaction IDs
  /// that the strategy cannot interpret.
  bool get usesOpaquePaginationCursor => false;

  /// Whether this strategy supports the given pagination mode
  bool supportsPaginationMode(Type paginationType) {
    return supportedPaginationModes.contains(paginationType);
  }

  /// Validates that the given pagination mode is supported by this strategy
  /// Throws UnsupportedError if not supported
  void validatePagination(TransactionPagination pagination) {
    if (!supportsPaginationMode(pagination.runtimeType)) {
      throw UnsupportedError(
        'Pagination mode ${pagination.runtimeType} is not supported by '
        '$runtimeType. Supported modes: $supportedPaginationModes',
      );
    }
  }
}
