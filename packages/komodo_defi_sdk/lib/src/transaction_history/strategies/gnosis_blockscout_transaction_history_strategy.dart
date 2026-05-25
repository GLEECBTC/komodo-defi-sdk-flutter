import 'package:http/http.dart' as http;
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/transaction_history/strategies/fixed_scale_decimal_string.dart';
import 'package:komodo_defi_sdk/src/transaction_history/strategies/public_explorer_history_pager.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Fetches Gnosis Chain native and ERC-20 history from Blockscout v2.
class GnosisBlockscoutTransactionStrategy extends TransactionHistoryStrategy {
  /// Creates a Gnosis Blockscout v2 transaction history strategy.
  GnosisBlockscoutTransactionStrategy({
    required this.pubkeyManager,
    http.Client? httpClient,
    String? baseUrl,
  }) : _client = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _helper = GnosisBlockscoutProtocolHelper(baseUrl: baseUrl) {
    _http = PublicExplorerJsonHttpClient(
      client: _client,
      ownsClient: _ownsClient,
      policy: const PublicExplorerHttpRetryPolicy(
        failureLabel: 'Failed to fetch Gnosis transaction history',
        networkFailureLabel:
            'Network error while fetching Gnosis transaction history',
        minRequestInterval: Duration(milliseconds: 350),
        maxAttempts: 4,
        jitter: Duration(milliseconds: 250),
      ),
    );
  }

  final http.Client _client;
  final bool _ownsClient;
  final GnosisBlockscoutProtocolHelper _helper;
  final PublicExplorerHistoryPager _pager = const PublicExplorerHistoryPager();
  late final PublicExplorerJsonHttpClient _http;

  /// Pubkey source used to resolve active wallet addresses for an asset.
  final PubkeyManager pubkeyManager;

  @override
  bool get usesOpaquePaginationCursor => true;

  @override
  Set<Type> get supportedPaginationModes => {
    PagePagination,
    TransactionBasedPagination,
  };

  @override
  bool supportsAsset(Asset asset) => _helper.supportsProtocol(asset);

  @override
  bool requiresKdfTransactionHistory(Asset asset) => false;

  @override
  Future<MyTxHistoryResponse> fetchTransactionHistory(
    ApiClient client,
    Asset asset,
    TransactionPagination pagination,
  ) async {
    if (!supportsAsset(asset)) {
      throw UnsupportedError(
        'Asset ${asset.id.name} is not supported by '
        'GnosisBlockscoutTransactionStrategy',
      );
    }

    validatePagination(pagination);

    try {
      final addresses = await _getAssetPubkeys(asset);
      final addressStrings = addresses
          .map((address) => address.address)
          .toList(growable: false);
      final limit = pagination.limit ?? 50;
      final cursors = pagination is TransactionBasedPagination
          ? _pager.decodeCursorMap(pagination.fromId)
          : <String, PublicExplorerCursorEntry>{};
      final selected = _pager.selectAddressPage(addressStrings, cursors);
      final page = selected == null
          ? const _BlockscoutPage(transactions: [])
          : await _fetchTransactionsForAddress(
              asset,
              selected.address,
              limit: limit,
              pageParams: _pageParamsFromCursor(selected.cursor),
            );
      final transactions = [...page.transactions]
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final nextCursors = _pager.nextCursorMap(
        addresses: addressStrings,
        currentCursors: cursors,
        selectedAddress: selected?.address,
        nextCursor: page.nextPageParams.isEmpty ? null : page.nextPageParams,
        pageProducedTransactions: transactions.isNotEmpty,
      );

      return _pager.buildResponse(
        transactions: transactions,
        nextCursors: nextCursors,
        limit: limit,
        pageNumber: pagination is PagePagination ? pagination.pageNumber : null,
      );
    } on Object catch (e) {
      throw HttpException('Error fetching Gnosis transaction history: $e');
    }
  }

  Future<List<PubkeyInfo>> _getAssetPubkeys(Asset asset) async {
    return (await pubkeyManager.getPubkeys(asset)).keys;
  }

  Future<_BlockscoutPage> _fetchTransactionsForAddress(
    Asset asset,
    String walletAddress, {
    required int limit,
    JsonMap? pageParams,
  }) async {
    final uri = _pageUri(
      _helper.getApiUrlForAsset(asset, walletAddress),
      limit: limit,
      pageParams: pageParams,
    );
    final response = await _http.getJson(uri);
    return _BlockscoutPage(
      transactions: _parseTransactions(
        response,
        asset: asset,
        walletAddress: walletAddress,
      ),
      nextPageParams: _nextPageParams(response),
    );
  }

  Uri _pageUri(Uri currentUri, {required int limit, JsonMap? pageParams}) {
    final queryParameters = {
      ...currentUri.queryParameters,
      if (pageParams == null || pageParams.isEmpty) 'items_count': '$limit',
      for (final entry in (pageParams ?? const <String, dynamic>{}).entries)
        if (entry.value != null && entry.value.toString().isNotEmpty)
          entry.key: entry.value.toString(),
    };
    return currentUri.replace(queryParameters: queryParameters);
  }

  JsonMap _nextPageParams(JsonMap response) {
    final nextPageParams = _jsonMap(response['next_page_params']);
    if (nextPageParams.isEmpty) {
      return const {};
    }
    return {
      for (final entry in nextPageParams.entries)
        if (entry.value != null && entry.value.toString().isNotEmpty)
          entry.key: entry.value.toString(),
    };
  }

  JsonMap? _pageParamsFromCursor(Object? cursor) {
    if (cursor == null) return null;
    final pageParams = _jsonMap(cursor);
    return pageParams.isEmpty ? null : pageParams;
  }

  List<TransactionInfo> _parseTransactions(
    JsonMap response, {
    required Asset asset,
    required String walletAddress,
  }) {
    final items = response.valueOrNull<JsonList>('items') ?? const [];
    return items
        .map((tx) => _parseTransaction(tx, asset, walletAddress))
        .nonNulls
        .toList();
  }

  TransactionInfo? _parseTransaction(
    dynamic raw,
    Asset asset,
    String walletAddress,
  ) {
    if (raw is! Map<String, dynamic>) return null;

    final isToken = asset.id.parentId != null;
    final txHash = _valueAsString(
      raw[isToken ? 'transaction_hash' : 'hash'] ?? raw['hash'],
    );
    if (txHash == null || txHash.isEmpty) return null;

    final fromAddress = _addressFrom(raw['from']);
    final toAddress = _addressFrom(raw['to']);
    final total = _jsonMap(raw['total']);
    final value = isToken
        ? _valueAsString(total['value'] ?? raw['value'])
        : _valueAsString(raw['value']);
    final decimals = _valueDecimals(raw, asset, isToken: isToken);
    final blockHeight = _valueAsInt(raw['block_number'] ?? raw['block']) ?? 0;
    final confirmations = _valueAsInt(raw['confirmations']) ?? 0;
    final timestamp = _timestampFrom(raw['timestamp']);
    final balanceChange = _balanceChange(
      walletAddress: walletAddress,
      fromAddress: fromAddress,
      toAddress: toAddress,
      value: value ?? '0',
      decimals: decimals,
    );

    return TransactionInfo(
      txHash: txHash,
      from: fromAddress == null ? const [] : [fromAddress],
      to: toAddress == null ? const [] : [toAddress],
      myBalanceChange: balanceChange,
      blockHeight: blockHeight,
      confirmations: confirmations,
      timestamp: timestamp,
      feeDetails: null,
      transactionFee: _valueAsString((raw['fee'] as JsonMap?)?['value']),
      coin: asset.id.id,
      internalId: _internalId(asset.id.id, txHash, raw),
      memo: null,
    );
  }

  String _balanceChange({
    required String walletAddress,
    required String? fromAddress,
    required String? toAddress,
    required String value,
    required int decimals,
  }) {
    final amount = BigInt.tryParse(value) ?? BigInt.zero;
    var change = BigInt.zero;
    if (_sameAddress(walletAddress, fromAddress)) change -= amount;
    if (_sameAddress(walletAddress, toAddress)) change += amount;
    return fixedScaleBigIntStringToDecimalString(change.toString(), decimals);
  }

  int _valueDecimals(JsonMap raw, Asset asset, {required bool isToken}) {
    final total = _jsonMap(raw['total']);
    final token = _jsonMap(raw['token']);
    final tokenInfo = _jsonMap(raw['token_info']);
    return _valueAsInt(
          total['decimals'] ??
              total['token_decimals'] ??
              token['decimals'] ??
              tokenInfo['decimals'] ??
              raw['decimals'],
        ) ??
        _assetDecimals(asset, fallback: isToken ? 18 : 18);
  }

  int _assetDecimals(Asset asset, {required int fallback}) {
    return asset.protocol.config.valueOrNull<int>('decimals') ??
        asset.protocol.config.valueOrNull<int>(
          'protocol',
          'protocol_data',
          'decimals',
        ) ??
        asset.id.chainId.decimals ??
        fallback;
  }

  bool _sameAddress(String address, String? other) =>
      other != null && address.toLowerCase() == other.toLowerCase();

  String _internalId(String coinId, String txHash, JsonMap raw) {
    final index = _valueAsString(
      raw['log_index'] ?? raw['index'] ?? raw['transaction_index'],
    );
    return index == null ? '$coinId:$txHash' : '$coinId:$txHash:$index';
  }

  String? _addressFrom(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is Map<String, dynamic>) {
      return _valueAsString(
        value['hash'] ?? value['address'] ?? value['address_hash'],
      );
    }
    return null;
  }

  String? _valueAsString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is int) return value.toString();
    if (value is BigInt) return value.toString();
    if (value is num) return value.toInt().toString();
    if (value is Map<String, dynamic>) {
      return _valueAsString(value['value']);
    }
    return null;
  }

  JsonMap _jsonMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, entryValue) => MapEntry('$key', entryValue));
    }
    return const {};
  }

  int? _valueAsInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  int _timestampFrom(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value > 9999999999 ? value ~/ 1000 : value;
    if (value is String) {
      final parsedInt = int.tryParse(value);
      if (parsedInt != null) {
        return parsedInt > 9999999999 ? parsedInt ~/ 1000 : parsedInt;
      }
      final parsedDate = DateTime.tryParse(value);
      return parsedDate == null
          ? 0
          : parsedDate.toUtc().millisecondsSinceEpoch ~/ 1000;
    }
    return 0;
  }

  /// Closes the owned HTTP client.
  void dispose() {
    _http.dispose();
  }
}

class _BlockscoutPage {
  const _BlockscoutPage({
    required this.transactions,
    this.nextPageParams = const {},
  });

  final List<TransactionInfo> transactions;
  final JsonMap nextPageParams;
}

/// Builds Blockscout v2 transaction history endpoints for Gnosis assets.
class GnosisBlockscoutProtocolHelper {
  /// Creates a helper with an optional Blockscout v2 base URL override.
  const GnosisBlockscoutProtocolHelper({String? baseUrl})
    : _baseUrl = baseUrl ?? 'https://gnosis.blockscout.com/api/v2';

  final String _baseUrl;

  /// Returns true when [asset] is a Gnosis native or ERC-20 asset.
  bool supportsProtocol(Asset asset) =>
      asset.protocol is Erc20Protocol &&
      asset.id.subClass == CoinSubClass.gnosis;

  /// Returns the Blockscout v2 history URL for [asset] and [address].
  Uri getApiUrlForAsset(Asset asset, String address) {
    if (!supportsProtocol(asset)) {
      throw UnsupportedError('Asset ${asset.id.id} is not a Gnosis EVM asset');
    }

    final contractAddress = asset.protocol.contractAddress;
    final queryParameters = asset.id.parentId == null
        ? null
        : {
            'type': 'ERC-20',
            if (contractAddress != null && contractAddress.isNotEmpty)
              'token': contractAddress,
          };
    final suffix = asset.id.parentId == null
        ? 'addresses/$address/transactions'
        : 'addresses/$address/token-transfers';
    final base = Uri.parse(_baseUrl);
    final path = '${base.path.replaceFirst(RegExp(r'/$'), '')}/$suffix';

    return base.replace(path: path, queryParameters: queryParameters);
  }
}
