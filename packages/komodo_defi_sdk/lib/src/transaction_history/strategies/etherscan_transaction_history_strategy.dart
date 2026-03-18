import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Strategy for fetching transaction history from the Etherscan proxy service.
/// Handles pagination client-side since the API currently doesn't support it.
class EtherscanTransactionStrategy extends TransactionHistoryStrategy {
  EtherscanTransactionStrategy({
    required this.pubkeyManager,
    http.Client? httpClient,
    String? baseUrl,
  }) : _client = httpClient ?? http.Client(),
       _protocolHelper = EtherscanProtocolHelper(baseUrl: baseUrl);

  final http.Client _client;
  final EtherscanProtocolHelper _protocolHelper;

  final PubkeyManager pubkeyManager;

  @override
  Set<Type> get supportedPaginationModes => {
    PagePagination,
    TransactionBasedPagination,
  };

  @override
  bool supportsAsset(Asset asset) => _protocolHelper.supportsProtocol(asset);

  @override
  bool requiresKdfTransactionHistory(Asset asset) {
    // Etherscan-backed history does not require KDF tx_history to be enabled
    // for pagination; streaming remains disabled for EVM in KDF.
    return false;
  }

  @override
  Future<MyTxHistoryResponse> fetchTransactionHistory(
    ApiClient client,
    Asset asset,
    TransactionPagination pagination,
  ) async {
    if (!supportsAsset(asset)) {
      throw UnsupportedError(
        'Asset ${asset.id.name} is not supported by EtherscanTransactionStrategy',
      );
    }

    // TODO! Remove after resolving tx history spamming issue in KW.
    if (kDebugMode) {
      return MyTxHistoryResponse.empty();
    }

    validatePagination(pagination);

    final url =
        _protocolHelper.getApiUrlForAsset(asset) ??
        (throw UnsupportedError(
          'No API URL found for asset ${asset.id.toJson()}',
        ));

    try {
      final addresses = await _getAssetPubkeys(asset);
      final allTransactions = <TransactionInfo>[];

      // Fetch transactions for each address
      for (final address in addresses) {
        final uri = url.replace(
          pathSegments: [...url.pathSegments, address.address],
          queryParameters: asset.protocol.isTestnet
              ? {'testnet': 'true'}
              : null,
        );
        // Add the address as the next path segment

        final response = await _executeRequest(uri);
        final transactions = _parseTransactions(response, asset.id.id);
        allTransactions.addAll(transactions);
      }

      // Sort by timestamp (newest first)
      allTransactions.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Apply pagination based on type
      final paginatedResults = switch (pagination) {
        final PagePagination p => _applyPagePagination(
          allTransactions,
          p.pageNumber,
          p.itemsPerPage,
        ),
        final TransactionBasedPagination t => _applyTransactionPagination(
          allTransactions,
          t.fromId,
          t.itemCount,
        ),
        _ => throw UnsupportedError(
          'Unsupported pagination type: ${pagination.runtimeType}',
        ),
      };

      final currentBlock = allTransactions.isNotEmpty
          ? allTransactions.first.blockHeight
          : 0;

      return MyTxHistoryResponse(
        mmrpc: RpcVersion.v2_0,
        currentBlock: currentBlock,
        fromId: paginatedResults.transactions.lastOrNull?.txHash,
        limit: paginatedResults.pageSize,
        skipped: paginatedResults.skipped,
        syncStatus: SyncStatusResponse(
          state: TransactionSyncStatusEnum.finished,
        ),
        total: allTransactions.length,
        totalPages: (allTransactions.length / paginatedResults.pageSize).ceil(),
        pageNumber: pagination is PagePagination ? pagination.pageNumber : null,
        pagingOptions: switch (pagination) {
          final PagePagination p => Pagination(pageNumber: p.pageNumber),
          final TransactionBasedPagination t => Pagination(fromId: t.fromId),
          _ => null,
        },
        transactions: paginatedResults.transactions,
      );
    } catch (e) {
      throw HttpException('Error fetching transaction history: $e');
    }
  }

  Future<List<PubkeyInfo>> _getAssetPubkeys(Asset asset) async {
    return (await pubkeyManager.getPubkeys(asset)).keys;
  }

  Future<JsonMap> _executeRequest(Uri uri) async {
    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) {
        throw HttpException(
          'Failed to fetch transaction history: ${response.statusCode}',
          uri: uri,
        );
      }

      return jsonFromString(response.body);
    } on http.ClientException catch (e) {
      throw HttpException(
        'Network error while fetching transaction history: ${e.message}',
        uri: uri,
      );
    }
  }

  List<TransactionInfo> _parseTransactions(JsonMap response, String coinId) {
    final result = response.value<JsonMap>('result');
    return result
        .value<JsonList>('transactions')
        .map(
          (tx) => TransactionInfo(
            txHash: tx.value<String>('tx_hash'),
            from: List<String>.from(tx.value('from')),
            to: List<String>.from(tx.value('to')),
            myBalanceChange: tx.value<String>('my_balance_change'),
            blockHeight: tx.value<int>('block_height'),
            confirmations: tx.value<int>('confirmations'),
            timestamp: tx.value<int>('timestamp'),
            feeDetails: tx.valueOrNull<JsonMap>('fee_details') != null
                ? FeeInfo.fromJson(
                    tx.value<JsonMap>('fee_details')
                      ..setIfAbsentOrEmpty('type', 'EthGas'),
                  )
                : null,
            coin: coinId,
            internalId: tx.value<String>('internal_id'),
            memo: tx.valueOrNull<String>('memo'),
          ),
        )
        .toList();
  }

  ({List<TransactionInfo> transactions, int skipped, int pageSize})
  _applyPagePagination(
    List<TransactionInfo> transactions,
    int pageNumber,
    int itemsPerPage,
  ) {
    final startIndex = (pageNumber - 1) * itemsPerPage;
    return (
      transactions: transactions.skip(startIndex).take(itemsPerPage).toList(),
      skipped: startIndex,
      pageSize: itemsPerPage,
    );
  }

  ({List<TransactionInfo> transactions, int skipped, int pageSize})
  _applyTransactionPagination(
    List<TransactionInfo> transactions,
    String fromId,
    int itemCount,
  ) {
    final startIndex = transactions.indexWhere((tx) => tx.txHash == fromId);
    if (startIndex == -1) {
      return (transactions: [], skipped: 0, pageSize: itemCount);
    }

    return (
      transactions: transactions.skip(startIndex + 1).take(itemCount).toList(),
      skipped: startIndex + 1,
      pageSize: itemCount,
    );
  }

  void dispose() {
    _client.close();
  }
}

/// Helper class for managing Etherscan protocol endpoints and URL construction
class EtherscanProtocolHelper {
  const EtherscanProtocolHelper({String? baseUrl})
    : _baseUrl = baseUrl ?? 'https://etherscan.gleec.com/api';

  final String _baseUrl;

  /// Returns true if the given protocol is supported by Etherscan
  bool supportsProtocol(Asset asset) {
    return asset.protocol is Erc20Protocol && getApiUrlForAsset(asset) != null;
  }

  /// Whether KDF transaction history should be enabled during activation.
  ///
  /// For EVM-compatible assets handled by the Etherscan strategy, we do not
  /// require KDF's tx_history to be enabled at activation because history is
  /// sourced externally and KDF does not support tx history streaming for EVM.
  /// This reduces unnecessary RPC work during activation.
  bool shouldEnableTransactionHistory(Asset asset) => false;

  /// Constructs the appropriate API URL for a given asset
  Uri? getApiUrlForAsset(Asset asset) {
    if (asset.protocol is! Erc20Protocol) return null;

    final endpoint = _getEndpointForAsset(asset);
    if (endpoint == null) return null;

    return Uri.parse(endpoint);
  }

  /// Returns the URL for fetching transaction history by hash.
  Uri transactionsByHashUrl(String txHash) =>
      Uri.parse('$_txByHashUrl/$txHash');

  String? _getEndpointForAsset(Asset asset) {
    final baseEndpoint = _getBaseEndpoint(asset.id);
    if (baseEndpoint == null) return null;

    final isParentChain = asset.id.parentId == null;

    if (isParentChain) {
      return baseEndpoint;
    }

    // For tokens, we need contract address in the path
    if (asset.protocol is! Erc20Protocol) {
      return null;
    }

    final protocol = asset.protocol as Erc20Protocol;
    final tokenContractAddress = protocol.contractAddress;
    if (tokenContractAddress == null || tokenContractAddress.isEmpty) {
      return null;
    }

    return '$baseEndpoint/$tokenContractAddress';
  }

  String? _getBaseEndpoint(AssetId id) {
    final isParentChain = id.parentId == null;
    return switch (id.subClass) {
      CoinSubClass.bep20 when isParentChain => _bnbUrl,
      CoinSubClass.bep20 => _bnbTokenUrl,
      CoinSubClass.matic when isParentChain => _maticUrl,
      CoinSubClass.matic => _maticTokenUrl,
      CoinSubClass.avx20 when isParentChain => _avaxUrl,
      CoinSubClass.avx20 => _avaxTokenUrl,
      CoinSubClass.moonriver when isParentChain => _mvrUrl,
      CoinSubClass.moonriver => _mvrTokenUrl,
      CoinSubClass.erc20 when isParentChain => _ethUrl,
      CoinSubClass.erc20 => _ethTokenUrl,
      CoinSubClass.arbitrum when isParentChain => _arbUrl,
      CoinSubClass.arbitrum => _arbTokenUrl,
      CoinSubClass.base when isParentChain => _ethBaseUrl,
      CoinSubClass.base => _ethBaseTokenUrl,
      CoinSubClass.rskSmartBitcoin => _rskUrl,
      CoinSubClass.moonbeam => _glmrUrl,
      CoinSubClass.ethereumClassic => _etcUrl,
      _ => null,
    };
  }

  /// Get an appropriate human-readable name for a given protocol
  String getProtocolDisplayName(Asset asset) {
    return asset.protocol.subClass.formatted;
  }

  String get _arbUrl => '$_baseUrl/v2/arb_tx_history';
  String get _avaxUrl => '$_baseUrl/v2/avax_tx_history';
  String get _ethBaseUrl => '$_baseUrl/v2/base_tx_history';
  String get _bnbUrl => '$_baseUrl/v2/bnb_tx_history';
  String get _ethUrl => '$_baseUrl/v2/eth_tx_history';
  String get _maticUrl => '$_baseUrl/v2/matic_tx_history';
  String get _mvrUrl => '$_baseUrl/v2/movr_tx_history';

  String get _arbTokenUrl => '$_baseUrl/v2/arb20_tx_history';
  String get _avaxTokenUrl => '$_baseUrl/v2/avx20_tx_history';
  String get _ethBaseTokenUrl => '$_baseUrl/v2/base20_tx_history';
  String get _bnbTokenUrl => '$_baseUrl/v2/bep20_tx_history';
  String get _ethTokenUrl => '$_baseUrl/v2/erc20_tx_history';
  String get _maticTokenUrl => '$_baseUrl/v2/plg20_tx_history';
  String get _mvrTokenUrl => '$_baseUrl/v2/mvr20_tx_history';

  String get _etcUrl => '$_baseUrl/v2/etc_tx_history';
  String get _glmrUrl => '$_baseUrl/v2/glmr_tx_history';
  String get _rskUrl => '$_baseUrl/v2/rsk_tx_history';
  String get _txByHashUrl => '$_baseUrl/v2/transactions_by_hash';
}
