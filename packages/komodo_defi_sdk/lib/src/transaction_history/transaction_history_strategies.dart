import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/_internal_exports.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Factory for creating appropriate transaction history strategies
class TransactionHistoryStrategyFactory {
  TransactionHistoryStrategyFactory(
    PubkeyManager pubkeyManager,
    KomodoDefiLocalAuth auth, {
    List<TransactionHistoryStrategy>? strategies,
    String? tronProApiKey,
  }) : _strategies =
           strategies ??
           [
             EtherscanTransactionStrategy(pubkeyManager: pubkeyManager),
             TronscanTransactionStrategy(
               pubkeyManager: pubkeyManager,
               tronProApiKey: tronProApiKey,
             ),
             V2TransactionStrategy(auth),
             const LegacyTransactionStrategy(),
             const ZhtlcTransactionStrategy(),
           ];

  final List<TransactionHistoryStrategy> _strategies;

  TransactionHistoryStrategy forAsset(Asset asset) {
    final strategy = _strategies.firstWhere(
      (strategy) => strategy.supportsAsset(asset),
      orElse: () =>
          throw UnsupportedError('No strategy found for asset ${asset.id.id}'),
    );

    return strategy;
  }
}

/// Strategy for fetching transaction history using the v2 API
class V2TransactionStrategy extends TransactionHistoryStrategy {
  const V2TransactionStrategy(this._auth);

  final KomodoDefiLocalAuth _auth;

  @override
  Set<Type> get supportedPaginationModes => {
    PagePagination,
    TransactionBasedPagination,
  };

  // TODO: Consider for the future how multi-account support will be handled.
  // The HistoryTarget could be added to the abstract strategy, but only if
  // it's applicable to all/most strategies.
  @override
  Future<MyTxHistoryResponse> fetchTransactionHistory(
    ApiClient client,
    Asset asset,
    TransactionPagination pagination,
    // {required HistoryTarget? target,}
  ) async {
    validatePagination(pagination);

    final isHdWallet = (await _auth.currentUser)?.isHd ?? false;

    return switch (pagination) {
      final PagePagination p => client.rpc.transactionHistory.myTxHistory(
        coin: asset.id.id,
        limit: p.itemsPerPage,
        pagingOptions: Pagination(pageNumber: p.pageNumber),
        target: isHdWallet
            ? const HdHistoryTarget.accountId(0)
            : IguanaHistoryTarget(),
      ),
      final TransactionBasedPagination t =>
        client.rpc.transactionHistory.myTxHistory(
          coin: asset.id.id,
          limit: t.itemCount,
          pagingOptions: Pagination(fromId: t.fromId),
          target: isHdWallet
              ? const HdHistoryTarget.accountId(0)
              : IguanaHistoryTarget(),
        ),
      _ => throw UnsupportedError(
        'Pagination mode ${pagination.runtimeType} not supported',
      ),
    };
  }

  static const List<Type> _supportedProtocols = [
    UtxoProtocol,
    QtumProtocol,
    TendermintProtocol,
  ];

  @override
  bool supportsAsset(Asset asset) =>
      _supportedProtocols.any((type) => asset.protocol.runtimeType == type);

  @override
  bool requiresKdfTransactionHistory(Asset asset) => true;
}

/// Strategy for fetching transaction history using the legacy API
class LegacyTransactionStrategy extends TransactionHistoryStrategy {
  const LegacyTransactionStrategy();

  @override
  Set<Type> get supportedPaginationModes => {
    PagePagination,
    TransactionBasedPagination,
  };

  @override
  Future<MyTxHistoryResponse> fetchTransactionHistory(
    ApiClient client,
    Asset asset,
    TransactionPagination pagination,
  ) async {
    validatePagination(pagination);

    return switch (pagination) {
      final PagePagination p => client.rpc.transactionHistory.myTxHistoryLegacy(
        coin: asset.id.id,
        limit: p.itemsPerPage,
        pageNumber: p.pageNumber,
      ),
      final TransactionBasedPagination t =>
        client.rpc.transactionHistory.myTxHistoryLegacy(
          coin: asset.id.id,
          limit: t.itemCount,
          fromId: t.fromId,
        ),
      _ => throw UnsupportedError(
        'Pagination mode ${pagination.runtimeType} not supported',
      ),
    };
  }

  @override
  bool supportsAsset(Asset asset) => asset.protocol is! ZhtlcProtocol;

  @override
  bool requiresKdfTransactionHistory(Asset asset) => true;
}

/// Strategy for fetching ZHTLC transaction history

///
