import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/transaction_history/strategies/etherscan_transaction_history_strategy.dart';
import 'package:komodo_defi_sdk/src/transaction_history/strategies/fixed_scale_decimal_string.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_history_strategies.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Fetches EVM history from a Blockscout instance's Etherscan-compatible API.
///
/// Exists because not every EVM chain the wallet supports is reachable through
/// the Etherscan proxy ([EtherscanTransactionStrategy]). The Gleec Chain
/// (GRC-20) is one such chain: it is not indexed by any Etherscan-family
/// explorer, so the proxy has no route for it. Without this strategy those
/// assets fall through to [LegacyTransactionStrategy], which reads a KDF
/// history store that activation deliberately leaves disabled for every EVM
/// asset - producing an empty list and, because an empty page is a *success*,
/// no error either.
///
/// **Opt-in per subclass.** [_supportedSubClasses] lists only chains whose
/// explorer has been verified to serve this API. `explorer_url` alone is not
/// evidence that an explorer speaks Blockscout, so new chains are added here
/// deliberately rather than inferred.
///
/// **Endpoint** is derived from the asset's own `explorer_url` config rather
/// than hardcoded, so mainnet and testnet resolve to their own instances.
///
/// **Pagination** follows the same contract as [EtherscanTransactionStrategy]:
/// the full (bounded) history is fetched, merged across the wallet's addresses
/// and sorted, then sliced client-side. The API does support `page`/`offset`,
/// but server-side paging cannot be applied across a merged multi-address set
/// without reintroducing the duplicates the merge exists to remove.
///
/// See the [Blockscout API docs](https://docs.blockscout.com/devs/apis/rpc).
class BlockscoutTransactionStrategy extends TransactionHistoryStrategy {
  /// Creates a strategy reading history from the asset's own Blockscout
  /// explorer. [apiUrlOverride] replaces the config-derived endpoint and is
  /// intended for tests.
  BlockscoutTransactionStrategy({
    required this.pubkeyManager,
    http.Client? httpClient,
    Uri? apiUrlOverride,
  }) : _client = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _apiUrlOverride = apiUrlOverride;

  /// Chains whose explorer has been verified to serve the Etherscan-compatible
  /// Blockscout API. Adding a subclass here is a claim that it was checked.
  static const Set<CoinSubClass> _supportedSubClasses = {CoinSubClass.grc20};

  /// Rows requested per address. The API caps `offset` server-side, so this is
  /// the practical ceiling on how deep one address's history is read.
  ///
  /// Histories longer than this are truncated at the oldest end rather than
  /// silently paged, which would misreport `fromId` as exhausted mid-history.
  /// [_truncatedAddresses] records when that happens so callers are not left
  /// believing the walk was complete.
  static const int _maxRowsPerAddress = 1000;

  final http.Client _client;
  final bool _ownsClient;
  final Uri? _apiUrlOverride;

  /// Provides the wallet's addresses for the asset being queried.
  final PubkeyManager pubkeyManager;

  /// Addresses whose history hit [_maxRowsPerAddress] on the last fetch.
  ///
  /// Exposed so a caller that cares about completeness can tell a short history
  /// from a truncated one; the strategy itself cannot surface this through
  /// [MyTxHistoryResponse].
  Set<String> get truncatedAddresses => Set.unmodifiable(_truncatedAddresses);
  final Set<String> _truncatedAddresses = <String>{};

  @override
  Set<Type> get supportedPaginationModes => {
    PagePagination,
    TransactionBasedPagination,
  };

  @override
  bool supportsAsset(Asset asset) =>
      asset.protocol is Erc20Protocol &&
      _supportedSubClasses.contains(asset.id.subClass) &&
      _apiUrlFor(asset) != null;

  /// History is sourced externally, so KDF's `tx_history` need not be enabled
  /// at activation - which matters because KDF cannot serve ETH-family history
  /// on web at all, and needs a `trace_filter`-capable node natively.
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
        'BlockscoutTransactionStrategy',
      );
    }

    validatePagination(pagination);

    final apiUrl =
        _apiUrlFor(asset) ??
        (throw UnsupportedError(
          'No Blockscout API URL found for asset ${asset.id.toJson()}',
        ));

    // A token asset reads the token-transfer log filtered to its contract; the
    // platform coin reads the native transaction list.
    //
    // Keyed on the contract address rather than [AssetId.parentId] on purpose.
    // `parentId` is only resolved when the asset registry supplies `knownIds`,
    // so an unresolved parent would silently route a token down the native
    // path - reporting raw 18-decimal amounts for a 6-decimal token and
    // deducting platform gas from a token balance. Having a contract is
    // intrinsic to being a token and cannot fail to resolve.
    final tokenContract = _contractAddress(asset);

    try {
      final addresses = await _walletAddresses(asset);
      _truncatedAddresses.clear();

      // Merged by hash: with several wallet addresses, a transfer between two
      // of them is returned once per address. Summing the per-address balance
      // changes renders a self-transfer as its true net cost (the fee) rather
      // than as two unrelated movements.
      final byHash = <String, TransactionInfo>{};

      for (final address in addresses) {
        final rows = await _fetchRows(
          apiUrl: apiUrl,
          address: address,
          tokenContract: tokenContract,
        );

        if (rows.length >= _maxRowsPerAddress) {
          _truncatedAddresses.add(address);
        }

        for (final row in rows) {
          final tx = tokenContract == null
              ? _nativeRowToTransactionInfo(
                  row: row,
                  viewerAddress: address,
                  asset: asset,
                )
              : _tokenRowToTransactionInfo(
                  row: row,
                  viewerAddress: address,
                  asset: asset,
                );
          if (tx == null) continue;

          final existing = byHash[tx.txHash];
          byHash[tx.txHash] = existing == null
              ? tx
              : _mergeTransactionInfo(existing, tx);
        }
      }

      final all = byHash.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final page = switch (pagination) {
        final PagePagination p => _applyPagePagination(
          all,
          p.pageNumber,
          p.itemsPerPage,
        ),
        final TransactionBasedPagination t => _applyTransactionPagination(
          all,
          t.fromId,
          t.itemCount,
        ),
        _ => throw UnsupportedError(
          'Unsupported pagination type: ${pagination.runtimeType}',
        ),
      };

      return MyTxHistoryResponse(
        mmrpc: RpcVersion.v2_0,
        currentBlock: all.isNotEmpty ? all.first.blockHeight : 0,
        // Null once the slice reaches the end, which is how the manager's
        // streaming loop learns to stop.
        fromId: page.hasMore ? page.transactions.lastOrNull?.txHash : null,
        limit: page.pageSize,
        skipped: page.skipped,
        syncStatus: SyncStatusResponse(
          state: TransactionSyncStatusEnum.finished,
        ),
        total: all.length,
        totalPages: page.pageSize > 0 ? (all.length / page.pageSize).ceil() : 0,
        pageNumber: pagination is PagePagination ? pagination.pageNumber : null,
        pagingOptions: switch (pagination) {
          final PagePagination p => Pagination(pageNumber: p.pageNumber),
          final TransactionBasedPagination t => Pagination(fromId: t.fromId),
          _ => null,
        },
        transactions: page.transactions,
      );
    } on HttpException {
      rethrow;
    } catch (e) {
      throw HttpException('Error fetching Blockscout transaction history: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // HTTP
  // ---------------------------------------------------------------------------

  Future<List<JsonMap>> _fetchRows({
    required Uri apiUrl,
    required String address,
    required String? tokenContract,
  }) async {
    final uri = apiUrl.replace(
      queryParameters: <String, String>{
        'module': 'account',
        'action': tokenContract == null ? 'txlist' : 'tokentx',
        'address': address,
        if (tokenContract != null) 'contractaddress': tokenContract,
        'sort': 'desc',
        'page': '1',
        'offset': '$_maxRowsPerAddress',
      },
    );

    final JsonMap json;
    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) {
        throw HttpException(
          'Blockscout request failed: ${response.statusCode}',
          uri: uri,
        );
      }
      json = jsonFromString(response.body);
    } on http.ClientException catch (e) {
      throw HttpException(
        'Network error while fetching Blockscout history: ${e.message}',
        uri: uri,
      );
    }

    // An address with no history answers `status: "0"` with the message
    // "No transactions found" and an empty result. That is an empty history,
    // not a failure - treating it as an error would reproduce the very bug
    // this strategy exists to fix, only louder.
    final result = json['result'];
    if (result is List) return result.whereType<JsonMap>().toList();

    // Some Etherscan-compatible deployments answer the no-history case with a
    // null/string result instead of an empty list, still under this message.
    final message = json.valueOrNull<String>('message') ?? '';
    if (message.toLowerCase().contains('no transactions found')) {
      return const [];
    }

    // Every other non-list envelope is an error report - a rate limit, an
    // invalid query, a backend failure - with the detail carried in `result`
    // as a string. Mapping those to an empty list would show the user "no
    // transactions" for a transient explorer failure and suppress the
    // manager's retry handling.
    final detail = [
      message,
      if (result is String) result,
    ].where((s) => s.isNotEmpty).join(' - ');
    throw HttpException('Blockscout error response: $detail', uri: uri);
  }

  // ---------------------------------------------------------------------------
  // Row -> TransactionInfo
  // ---------------------------------------------------------------------------

  /// Maps a `txlist` row. The fee is denominated in this same coin, so it is
  /// part of the balance change for an outgoing transfer.
  TransactionInfo? _nativeRowToTransactionInfo({
    required JsonMap row,
    required String viewerAddress,
    required Asset asset,
  }) {
    final hash = row.valueOrNull<String>('hash');
    if (hash == null || hash.isEmpty) return null;

    final from = row.valueOrNull<String>('from') ?? '';
    final to = row.valueOrNull<String>('to') ?? '';
    final isOut = _addressesEqual(from, viewerAddress);
    final isIn = _addressesEqual(to, viewerAddress);
    if (!isOut && !isIn) return null;

    final decimals = _decimals(asset);
    // A reverted transaction moves no value but still burns the gas it used.
    final reverted = row.valueOrNull<String>('isError') == '1';
    final valueWei = reverted ? '0' : (row.valueOrNull<String>('value') ?? '0');
    final feeWei = _feeWei(row);

    final value = fixedScaleBigIntStringToDecimalString(valueWei, decimals);
    final fee = fixedScaleBigIntStringToDecimalString(feeWei, decimals);

    final received = isIn ? value : '0';
    // The fee belongs in `spent_by_me` so the amount shown as leaving the
    // wallet matches what the balance actually lost.
    final spent = isOut ? _addDecimalStrings(value, fee) : '0';
    final balanceChange = _subtractDecimalStrings(received, spent);

    return TransactionInfo(
      txHash: hash,
      from: [from],
      to: [if (to.isNotEmpty) to],
      myBalanceChange: balanceChange,
      blockHeight: _intOf(row, 'blockNumber'),
      confirmations: _intOf(row, 'confirmations'),
      timestamp: _intOf(row, 'timeStamp'),
      feeDetails: _ethGasFee(row, feeCoin: asset.id.id, decimals: decimals),
      coin: asset.id.id,
      internalId: hash,
      spentByMe: spent,
      receivedByMe: received,
      memo: null,
    );
  }

  /// Maps a `tokentx` row. Gas is paid in the platform coin, never in the
  /// token, so it is deliberately absent from this asset's balance change.
  TransactionInfo? _tokenRowToTransactionInfo({
    required JsonMap row,
    required String viewerAddress,
    required Asset asset,
  }) {
    final hash = row.valueOrNull<String>('hash');
    if (hash == null || hash.isEmpty) return null;

    final from = row.valueOrNull<String>('from') ?? '';
    final to = row.valueOrNull<String>('to') ?? '';
    final isOut = _addressesEqual(from, viewerAddress);
    final isIn = _addressesEqual(to, viewerAddress);
    if (!isOut && !isIn) return null;

    // Trust the row's own scale over the config: the token being queried is
    // fixed by `contractaddress`, and the explorer reports its real decimals.
    final decimals =
        int.tryParse(row.valueOrNull<String>('tokenDecimal') ?? '') ??
        _decimals(asset);

    final value = fixedScaleBigIntStringToDecimalString(
      row.valueOrNull<String>('value') ?? '0',
      decimals,
    );

    final received = isIn ? value : '0';
    final spent = isOut ? value : '0';

    return TransactionInfo(
      txHash: hash,
      from: [from],
      to: [if (to.isNotEmpty) to],
      myBalanceChange: _subtractDecimalStrings(received, spent),
      blockHeight: _intOf(row, 'blockNumber'),
      confirmations: _intOf(row, 'confirmations'),
      timestamp: _intOf(row, 'timeStamp'),
      // Denominated in the platform coin, not this token.
      feeDetails: _ethGasFee(
        row,
        feeCoin: _platformCoinId(asset),
        decimals: _platformDecimals,
      ),
      coin: asset.id.id,
      internalId: hash,
      spentByMe: spent,
      receivedByMe: received,
      memo: null,
    );
  }

  /// Combines two views of the same transaction seen from different wallet
  /// addresses. Values sum, so a transfer between the wallet's own addresses
  /// nets out to its fee.
  TransactionInfo _mergeTransactionInfo(TransactionInfo a, TransactionInfo b) {
    return TransactionInfo(
      txHash: a.txHash,
      from: <String>{...a.from, ...b.from}.toList(),
      to: <String>{...a.to, ...b.to}.toList(),
      myBalanceChange: _addDecimalStrings(a.myBalanceChange, b.myBalanceChange),
      blockHeight: a.blockHeight,
      confirmations: a.confirmations > b.confirmations
          ? a.confirmations
          : b.confirmations,
      timestamp: a.timestamp > b.timestamp ? a.timestamp : b.timestamp,
      feeDetails: a.feeDetails ?? b.feeDetails,
      coin: a.coin,
      internalId: a.internalId,
      spentByMe: _addDecimalStrings(a.spentByMe ?? '0', b.spentByMe ?? '0'),
      receivedByMe: _addDecimalStrings(
        a.receivedByMe ?? '0',
        b.receivedByMe ?? '0',
      ),
      memo: a.memo ?? b.memo,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// The Blockscout `/api` endpoint for [asset], derived from its configured
  /// explorer rather than a hardcoded host.
  Uri? _apiUrlFor(Asset asset) {
    if (_apiUrlOverride != null) return _apiUrlOverride;

    final base = asset.protocol.explorerPattern.baseUrl;
    if (base == null || !base.hasAuthority) return null;

    return base.replace(
      path: '${_stripTrailingSlash(base.path)}/api',
      query: '',
      fragment: '',
    );
  }

  static String _stripTrailingSlash(String path) =>
      path.endsWith('/') ? path.substring(0, path.length - 1) : path;

  /// The token contract for a token asset, or null for a platform coin.
  String? _contractAddress(Asset asset) {
    final config = asset.protocol.config;
    final contract =
        config.valueOrNull<String>('contract_address') ??
        config.valueOrNull<String>(
          'protocol',
          'protocol_data',
          'contract_address',
        );
    return (contract == null || contract.isEmpty) ? null : contract;
  }

  /// The coin gas is billed in. Falls back to the config's declared platform
  /// when [AssetId.parentId] is unresolved, so a token never mislabels its fee
  /// as being denominated in itself.
  String _platformCoinId(Asset asset) =>
      asset.id.parentId?.id ??
      asset.protocol.config.valueOrNull<String>(
        'protocol',
        'protocol_data',
        'platform',
      ) ??
      asset.protocol.config.valueOrNull<String>('parent_coin') ??
      asset.id.id;

  int _decimals(Asset asset) =>
      asset.protocol.config.valueOrNull<int>('decimals') ?? 18;

  /// EVM gas is always denominated in the 18-decimal platform coin. A token's
  /// own `decimals` must never be used to scale it - a 6-decimal token would
  /// otherwise report a fee a trillion times too large.
  static const int _platformDecimals = 18;

  Future<List<String>> _walletAddresses(Asset asset) async {
    final pubkeys = await pubkeyManager.getPubkeys(asset);
    final seen = <String>{};
    return [
      for (final key in pubkeys.keys)
        if (key.address.isNotEmpty && seen.add(key.address.toLowerCase()))
          key.address,
    ];
  }

  static bool _addressesEqual(String a, String b) =>
      a.toLowerCase() == b.toLowerCase();

  static int _intOf(JsonMap row, String key) {
    final raw = row[key];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  /// `gasUsed * gasPrice`, in wei, as an exact integer string.
  static String _feeWei(JsonMap row) {
    final gasUsed = BigInt.tryParse(row.valueOrNull<String>('gasUsed') ?? '');
    final gasPrice = BigInt.tryParse(row.valueOrNull<String>('gasPrice') ?? '');
    if (gasUsed == null || gasPrice == null) return '0';
    return (gasUsed * gasPrice).toString();
  }

  static FeeInfo? _ethGasFee(
    JsonMap row, {
    required String feeCoin,
    required int decimals,
  }) {
    final gasUsed = int.tryParse(row.valueOrNull<String>('gasUsed') ?? '');
    final gasPriceWei = row.valueOrNull<String>('gasPrice');
    if (gasUsed == null || gasPriceWei == null) return null;

    return FeeInfo.ethGas(
      coin: feeCoin,
      gasPrice: Decimal.parse(
        fixedScaleBigIntStringToDecimalString(gasPriceWei, decimals),
      ),
      gas: gasUsed,
      totalGasFee: Decimal.parse(
        fixedScaleBigIntStringToDecimalString(_feeWei(row), decimals),
      ),
    );
  }

  static String _addDecimalStrings(String a, String b) =>
      (Decimal.parse(a) + Decimal.parse(b)).toString();

  static String _subtractDecimalStrings(String a, String b) =>
      (Decimal.parse(a) - Decimal.parse(b)).toString();

  // ---------------------------------------------------------------------------
  // Client-side pagination
  // ---------------------------------------------------------------------------

  _Page _applyPagePagination(
    List<TransactionInfo> transactions,
    int pageNumber,
    int itemsPerPage,
  ) {
    final startIndex = (pageNumber - 1) * itemsPerPage;
    final slice = transactions.skip(startIndex).take(itemsPerPage).toList();
    return _Page(
      transactions: slice,
      skipped: startIndex,
      pageSize: itemsPerPage,
      hasMore: startIndex + slice.length < transactions.length,
    );
  }

  _Page _applyTransactionPagination(
    List<TransactionInfo> transactions,
    String fromId,
    int itemCount,
  ) {
    final startIndex = transactions.indexWhere((tx) => tx.txHash == fromId);
    if (startIndex == -1) {
      return _Page(
        transactions: const [],
        skipped: 0,
        pageSize: itemCount,
        hasMore: false,
      );
    }

    final slice = transactions.skip(startIndex + 1).take(itemCount).toList();
    return _Page(
      transactions: slice,
      skipped: startIndex + 1,
      pageSize: itemCount,
      hasMore: startIndex + 1 + slice.length < transactions.length,
    );
  }

  /// Releases the HTTP client if it was internally created.
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

class _Page {
  const _Page({
    required this.transactions,
    required this.skipped,
    required this.pageSize,
    required this.hasMore,
  });

  final List<TransactionInfo> transactions;
  final int skipped;
  final int pageSize;
  final bool hasMore;
}
