import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Fetches TRX and TRC-20 (on TRX) history from the TRONSCAN HTTP API.
///
/// See [TRONSCAN transactions & transfers](https://docs.tronscan.org/api-endpoints/transactions-and-transfers)
/// and [API keys](https://docs.tronscan.org/getting-started/api-keys).
class TronscanTransactionStrategy extends TransactionHistoryStrategy {
  TronscanTransactionStrategy({
    required this.pubkeyManager,
    http.Client? httpClient,
    this.tronProApiKey,
    String? apiHostOverride,
  }) : _client = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _apiHostOverride = apiHostOverride;

  static const int _pageSize = 200;

  /// Hard cap on rows pulled from TRONSCAN per strategy invocation to bound memory.
  static const int _maxFetchedRows = 10000;

  static const int _maxHttpAttempts = 6;

  final http.Client _client;
  final bool _ownsClient;
  final String? _apiHostOverride;
  final PubkeyManager pubkeyManager;

  /// Optional key; sent as `TRON-PRO-API-KEY` for higher quotas per TRONSCAN docs.
  final String? tronProApiKey;

  @override
  Set<Type> get supportedPaginationModes => {
    PagePagination,
    TransactionBasedPagination,
  };

  @override
  bool supportsAsset(Asset asset) {
    if (asset.protocol is TrxProtocol) return true;
    if (asset.protocol is Trc20Protocol) {
      return (asset.protocol as Trc20Protocol).platform == 'TRX';
    }
    return false;
  }

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
        'Asset ${asset.id.name} is not supported by TronscanTransactionStrategy',
      );
    }

    validatePagination(pagination);

    final host = _apiHostOverride ?? _defaultApiHost(asset.protocol);
    final addresses = await _getAssetPubkeys(asset);
    final byHash = <String, TransactionInfo>{};

    try {
      for (final pubkey in addresses) {
        final txs = switch (asset.protocol) {
          TrxProtocol() => await _fetchTrxTransfers(
            host: host,
            address: pubkey.address,
            asset: asset,
          ),
          Trc20Protocol() => await _fetchTrc20Transfers(
            host: host,
            address: pubkey.address,
            asset: asset,
          ),
          _ => <TransactionInfo>[],
        };
        for (final tx in txs) {
          final existing = byHash[tx.txHash];
          if (existing == null) {
            byHash[tx.txHash] = tx;
          } else {
            byHash[tx.txHash] = _mergeTransactionInfo(existing, tx);
          }
        }
      }

      final allTransactions = byHash.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

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
      throw HttpException('Error fetching Tronscan transaction history: $e');
    }
  }

  Future<List<PubkeyInfo>> _getAssetPubkeys(Asset asset) async {
    return (await pubkeyManager.getPubkeys(asset)).keys;
  }

  String _defaultApiHost(ProtocolClass protocol) {
    return protocol.isTestnet
        ? 'nileapi.tronscan.org'
        : 'apilist.tronscanapi.com';
  }

  int _decimals(Asset asset) =>
      asset.protocol.config.valueOrNull<int>('decimals') ?? 6;

  Future<List<TransactionInfo>> _fetchTrxTransfers({
    required String host,
    required String address,
    required Asset asset,
  }) async {
    final decimals = _decimals(asset);
    final out = <TransactionInfo>[];
    var start = 0;

    while (out.length < _maxFetchedRows) {
      final uri = Uri.https(host, '/api/transfer', {
        'address': address,
        'sort': '-timestamp',
        'count': 'true',
        'start': '$start',
        'limit': '$_pageSize',
        'filterTokenValue': '1',
      });

      final json = await _getJson(uri);
      final data = json.valueOrNull<JsonList>('data') ?? const [];
      if (data.isEmpty) break;

      for (final row in data) {
        if (out.length >= _maxFetchedRows) break;
        if (!_isSuccessfulTronscanRow(row)) continue;
        final tx = _transferRowToTransactionInfo(
          row: row,
          viewerAddress: address,
          coinId: asset.id.id,
          decimals: decimals,
        );
        if (tx != null) out.add(tx);
      }

      start += data.length;
      final total = json.valueOrNull<int>('total');
      if (data.length < _pageSize) break;
      if (total != null && start >= total) break;
    }

    return out;
  }

  Future<List<TransactionInfo>> _fetchTrc20Transfers({
    required String host,
    required String address,
    required Asset asset,
  }) async {
    final contract = _trc20ContractAddress(asset);
    if (contract == null || contract.isEmpty) {
      return [];
    }

    final decimals = _tokenDecimalsFromRowOrAsset(asset);
    final out = <TransactionInfo>[];
    var start = 0;

    while (out.length < _maxFetchedRows) {
      final uri = Uri.https(host, '/api/token_trc20/transfers', {
        'relatedAddress': address,
        'contract_address': contract,
        'start': '$start',
        'limit': '$_pageSize',
        'confirm': 'true',
      });

      final json = await _getJson(uri);
      final list = json.valueOrNull<JsonList>('token_transfers') ?? const [];
      if (list.isEmpty) break;

      for (final row in list) {
        if (out.length >= _maxFetchedRows) break;
        if (!_isSuccessfulTrc20Row(row)) continue;
        final tx = _trc20RowToTransactionInfo(
          row: row,
          viewerAddress: address,
          coinId: asset.id.id,
          decimals: decimals,
        );
        if (tx != null) out.add(tx);
      }

      start += list.length;
      final total = json.valueOrNull<int>('total');
      if (list.length < _pageSize) break;
      if (total != null && start >= total) break;
    }

    return out;
  }

  String? _trc20ContractAddress(Asset asset) {
    final config = asset.protocol.config;
    return config.valueOrNull<String>('contract_address') ??
        config.valueOrNull<String>(
          'protocol',
          'protocol_data',
          'contract_address',
        );
  }

  int _tokenDecimalsFromRowOrAsset(Asset asset) {
    return asset.protocol.config.valueOrNull<int>('decimals') ?? 18;
  }

  bool _isSuccessfulTronscanRow(JsonMap row) {
    final confirmed = row.valueOrNull<bool>('confirmed');
    if (confirmed == false) return false;
    final ret = row.valueOrNull<String>('contractRet');
    if (ret != null && ret != 'SUCCESS') return false;
    return true;
  }

  bool _isSuccessfulTrc20Row(JsonMap row) {
    final confirmed = row.valueOrNull<bool>('confirmed');
    if (confirmed == false) return false;
    final ret = row.valueOrNull<String>('contractRet');
    if (ret != null && ret != 'SUCCESS') return false;
    return true;
  }

  TransactionInfo? _transferRowToTransactionInfo({
    required JsonMap row,
    required String viewerAddress,
    required String coinId,
    required int decimals,
  }) {
    final hash = row.valueOrNull<String>('transactionHash');
    if (hash == null || hash.isEmpty) return null;

    final from = row.valueOrNull<String>('transferFromAddress') ?? '';
    final to = row.valueOrNull<String>('transferToAddress') ?? '';
    final amountRaw = row.valueOrNull<num>('amount');
    if (amountRaw == null) return null;

    final block = row.valueOrNull<int>('block') ?? 0;
    final tsMs = row.valueOrNull<int>('timestamp') ?? 0;
    final tsSec = tsMs ~/ 1000;

    final amountSun = amountRaw.toInt();
    final absHuman = _rawIntToDecimalString(amountSun, decimals);

    final isOut = _tronAddressesEqual(from, viewerAddress);
    final isIn = _tronAddressesEqual(to, viewerAddress);
    if (!isOut && !isIn) return null;

    String signedBalance;
    String? spentByMe;
    String? receivedByMe;
    if (isOut && !isIn) {
      signedBalance = '-$absHuman';
      spentByMe = absHuman;
      receivedByMe = '0';
    } else if (isIn && !isOut) {
      signedBalance = absHuman;
      spentByMe = '0';
      receivedByMe = absHuman;
    } else {
      signedBalance = '0';
      spentByMe = absHuman;
      receivedByMe = absHuman;
    }

    final confirmations = row.valueOrNull<bool>('confirmed') == true ? 1 : 0;

    return TransactionInfo(
      txHash: hash,
      from: [from],
      to: [to],
      myBalanceChange: signedBalance,
      blockHeight: block,
      confirmations: confirmations,
      timestamp: tsSec,
      feeDetails: null,
      coin: coinId,
      internalId: hash,
      spentByMe: spentByMe,
      receivedByMe: receivedByMe,
      memo: null,
    );
  }

  TransactionInfo? _trc20RowToTransactionInfo({
    required JsonMap row,
    required String viewerAddress,
    required String coinId,
    required int decimals,
  }) {
    final hash = row.valueOrNull<String>('transaction_id');
    if (hash == null || hash.isEmpty) return null;

    final from = row.valueOrNull<String>('from_address') ?? '';
    final to = row.valueOrNull<String>('to_address') ?? '';
    final quant = row.valueOrNull<String>('quant');
    if (quant == null || quant.isEmpty) return null;

    final tokenInfo = row.valueOrNull<JsonMap>('tokenInfo');
    final dec = tokenInfo?.valueOrNull<int>('tokenDecimal') ?? decimals;

    final block = row.valueOrNull<int>('block') ?? 0;
    final tsMs = row.valueOrNull<int>('block_ts') ?? 0;
    final tsSec = tsMs ~/ 1000;

    final absHuman = _rawStringToDecimalString(quant, dec);

    final isOut = _tronAddressesEqual(from, viewerAddress);
    final isIn = _tronAddressesEqual(to, viewerAddress);
    if (!isOut && !isIn) return null;

    String signedBalance;
    String? spentByMe;
    String? receivedByMe;
    if (isOut && !isIn) {
      signedBalance = '-$absHuman';
      spentByMe = absHuman;
      receivedByMe = '0';
    } else if (isIn && !isOut) {
      signedBalance = absHuman;
      spentByMe = '0';
      receivedByMe = absHuman;
    } else {
      signedBalance = '0';
      spentByMe = absHuman;
      receivedByMe = absHuman;
    }

    final confirmations = row.valueOrNull<bool>('confirmed') == true ? 1 : 0;

    return TransactionInfo(
      txHash: hash,
      from: [from],
      to: [to],
      myBalanceChange: signedBalance,
      blockHeight: block,
      confirmations: confirmations,
      timestamp: tsSec,
      feeDetails: null,
      coin: coinId,
      internalId: hash,
      spentByMe: spentByMe,
      receivedByMe: receivedByMe,
      memo: null,
    );
  }

  bool _tronAddressesEqual(String a, String b) {
    return a.toLowerCase() == b.toLowerCase();
  }

  String _rawIntToDecimalString(int raw, int decimals) {
    if (decimals <= 0) return raw.toString();
    var divisor = Decimal.one;
    for (var i = 0; i < decimals; i++) {
      divisor *= Decimal.fromInt(10);
    }
    final quotient = Decimal.fromInt(raw) / divisor;
    return quotient.toString();
  }

  String _rawStringToDecimalString(String raw, int decimals) {
    if (decimals <= 0) return raw;
    var divisor = Decimal.one;
    for (var i = 0; i < decimals; i++) {
      divisor *= Decimal.fromInt(10);
    }
    final quotient = Decimal.parse(raw) / divisor;
    return quotient.toString();
  }

  TransactionInfo _mergeTransactionInfo(TransactionInfo a, TransactionInfo b) {
    final net =
        (Decimal.parse(a.myBalanceChange) + Decimal.parse(b.myBalanceChange))
            .toString();
    final spentA = a.spentByMe != null
        ? Decimal.parse(a.spentByMe!)
        : Decimal.zero;
    final spentB = b.spentByMe != null
        ? Decimal.parse(b.spentByMe!)
        : Decimal.zero;
    final recvA = a.receivedByMe != null
        ? Decimal.parse(a.receivedByMe!)
        : Decimal.zero;
    final recvB = b.receivedByMe != null
        ? Decimal.parse(b.receivedByMe!)
        : Decimal.zero;

    final from = <String>{...a.from, ...b.from}.toList();
    final to = <String>{...a.to, ...b.to}.toList();

    return TransactionInfo(
      txHash: a.txHash,
      from: from.toList(),
      to: to.toList(),
      myBalanceChange: net,
      blockHeight: a.blockHeight,
      confirmations: a.confirmations > b.confirmations
          ? a.confirmations
          : b.confirmations,
      timestamp: a.timestamp > b.timestamp ? a.timestamp : b.timestamp,
      feeDetails: a.feeDetails ?? b.feeDetails,
      coin: a.coin,
      internalId: a.internalId,
      spentByMe: (spentA + spentB).toString(),
      receivedByMe: (recvA + recvB).toString(),
      memo: a.memo ?? b.memo,
    );
  }

  Future<JsonMap> _getJson(Uri uri) async {
    final headers = <String, String>{};
    final key = tronProApiKey;
    if (key != null && key.isNotEmpty) {
      headers['TRON-PRO-API-KEY'] = key;
    }

    final random = math.Random();
    var attempt = 0;
    var backoff = const Duration(milliseconds: 200);
    const maxBackoff = Duration(seconds: 5);

    while (true) {
      try {
        final response = await _client.get(uri, headers: headers);
        if (response.statusCode == 200) {
          return jsonFromString(response.body);
        }

        final retriable =
            response.statusCode == 429 || response.statusCode == 503;
        if (retriable && attempt < _maxHttpAttempts - 1) {
          final retryAfter = _retryAfterDuration(response);
          final jitter = Duration(milliseconds: random.nextInt(250));
          final baseWait = retryAfter ?? backoff;
          await Future<void>.delayed(baseWait + jitter);
          attempt++;
          final doubled = backoff.inMilliseconds * 2;
          backoff = doubled > maxBackoff.inMilliseconds
              ? maxBackoff
              : Duration(milliseconds: doubled);
          continue;
        }

        throw HttpException(
          'Tronscan request failed: ${response.statusCode}',
          uri: uri,
        );
      } on http.ClientException catch (e) {
        if (attempt >= _maxHttpAttempts - 1) {
          throw HttpException(
            'Network error while fetching Tronscan history: ${e.message}',
            uri: uri,
          );
        }
        final jitter = Duration(milliseconds: random.nextInt(250));
        await Future<void>.delayed(backoff + jitter);
        attempt++;
        backoff = backoff.inMilliseconds * 2 > maxBackoff.inMilliseconds
            ? maxBackoff
            : Duration(milliseconds: backoff.inMilliseconds * 2);
      }
    }
  }

  Duration? _retryAfterDuration(http.Response response) {
    final header = response.headers['retry-after'];
    if (header == null) return null;
    final seconds = int.tryParse(header.trim());
    if (seconds == null) return null;
    return Duration(seconds: seconds.clamp(0, 3600));
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
    if (_ownsClient) {
      _client.close();
    }
  }
}
