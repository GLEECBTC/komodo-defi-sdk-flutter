import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/transaction_history/strategies/fixed_scale_decimal_string.dart';
import 'package:komodo_defi_sdk/src/transaction_history/strategies/tron_grid_address_codec.dart';
import 'package:komodo_defi_sdk/src/transaction_history/strategies/tron_grid_cursor_codec.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Fetches TRX and TRC-20 (on TRX) history from the TRONGrid HTTP API,
/// one page at a time so the manager can stream results to the UI.
///
/// Uses the public TRONGrid API which does **not** require an API key.
/// Rate-limited to 3 RPS with a 3-second suspension on violation.
///
/// **Pagination contract:** TRONGrid uses cursor-based pagination via an opaque
/// `fingerprint` token. This strategy stores the fingerprint in
/// [MyTxHistoryResponse.fromId] so the manager can pass it back via
/// [TransactionBasedPagination.fromId] on the next call. When `fromId` is
/// `null`, there are no more pages.
///
/// See [TRX transactions](https://developers.tron.network/reference/get-transaction-info-by-account-address)
/// and [TRC-20 transfers](https://developers.tron.network/reference/trc20-transaction-information-by-account-address).
class TronGridTransactionStrategy extends TransactionHistoryStrategy {
  /// Creates a strategy that fetches TRON history from TRONGrid page-by-page.
  TronGridTransactionStrategy({
    required this.pubkeyManager,
    http.Client? httpClient,
    this.tronProApiKey,
    String? apiHostOverride,
  }) : _client = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _apiHostOverride = apiHostOverride;

  /// Rows per TRONGrid API request (their maximum).
  static const int _gridPageSize = 200;

  /// Cursor marker for addresses that haven't been fetched yet. Used to enable
  /// per-address incremental streaming: the strategy returns results as soon as
  /// the first address yields data, encoding remaining addresses with this
  /// marker so the manager's streaming loop fetches them on subsequent calls.
  static const String _kPending = '__pending__';

  /// For TRX (where rows are filtered client-side for TransferContract), fetch
  /// up to this many TRONGrid pages per [fetchTransactionHistory] call so a
  /// single invocation still returns a meaningful batch.
  static const int _maxInternalPages = 3;

  static const int _maxHttpAttempts = 6;

  /// Minimum gap between HTTP requests to stay within 3 RPS.
  static const Duration _minRequestInterval = Duration(milliseconds: 350);

  final http.Client _client;
  final bool _ownsClient;
  final String? _apiHostOverride;

  /// Provides public-key / address data for the asset being queried.
  final PubkeyManager pubkeyManager;

  /// Retained for backward compatibility; TRONGrid does not require a key.
  final String? tronProApiKey;

  DateTime _lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  bool get usesOpaquePaginationCursor => true;

  @override
  /// Both page-based (initial fetch) and cursor-based (streaming) pagination.
  Set<Type> get supportedPaginationModes => {
    PagePagination,
    TransactionBasedPagination,
  };

  @override
  bool supportsAsset(Asset asset) => switch (asset.protocol) {
    TrxProtocol() => true,
    Trc20Protocol(:final platform) => platform == 'TRX',
    _ => false,
  };

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
        'TronGridTransactionStrategy',
      );
    }

    validatePagination(pagination);

    final host = _apiHostOverride ?? _defaultApiHost(asset.protocol);
    final addresses = await _getAssetPubkeys(asset);
    final limit = pagination.limit ?? 50;

    // Decode per-address cursors. On the first call (PagePagination) the map
    // is empty so every address starts from the beginning. On subsequent calls
    // the map contains only addresses that still have remaining pages.
    final cursors =
        pagination is TransactionBasedPagination &&
            !_looksLikeTransactionHash(pagination.fromId)
        ? decodeTronGridCursorMap(pagination.fromId)
        : <String, String>{};

    final byHash = <String, TransactionInfo>{};
    final nextCursors = <String, String>{};

    try {
      for (var i = 0; i < addresses.length; i++) {
        final addr = addresses[i].address;

        // On a continuation call, skip addresses already exhausted (absent
        // from the cursor map). The empty-key wildcard ('') from the single-
        // address fast path matches any address.
        if (cursors.isNotEmpty &&
            !cursors.containsKey(addr) &&
            !cursors.containsKey('')) {
          continue;
        }

        // Resolve fingerprint: exact address key first, then wildcard ('').
        // The _kPending marker means "not yet started" — treat as null.
        var fp = cursors[addr] ?? cursors[''];
        if (fp == _kPending) fp = null;

        final result = switch (asset.protocol) {
          TrxProtocol() => await _fetchTrxPage(
            host: host,
            address: addr,
            asset: asset,
            fingerprint: fp,
            limit: limit,
          ),
          Trc20Protocol() => await _fetchTrc20Page(
            host: host,
            address: addr,
            asset: asset,
            fingerprint: fp,
          ),
          _ => const _PageResult(transactions: []),
        };

        for (final tx in result.transactions) {
          final h = tx.txHash;
          final existing = byHash[h];
          byHash[h] = existing == null
              ? tx
              : _mergeTransactionInfo(existing, tx);
        }

        if (result.nextFingerprint != null) {
          nextCursors[addr] = result.nextFingerprint!;
        }

        // Yield results early: if we already have transactions and there are
        // remaining addresses, encode them as pending in the cursor so the
        // manager's streaming loop fetches them on the next call.
        if (byHash.isNotEmpty && i < addresses.length - 1) {
          for (var j = i + 1; j < addresses.length; j++) {
            final pending = addresses[j].address;
            if (!nextCursors.containsKey(pending)) {
              nextCursors[pending] = cursors[pending] ?? _kPending;
            }
          }
          break;
        }
      }

      final transactions = byHash.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final currentBlock = transactions.isNotEmpty
          ? transactions.first.blockHeight
          : 0;

      final cursorString = nextCursors.isEmpty
          ? null
          : encodeTronGridCursorMap(nextCursors);

      return MyTxHistoryResponse(
        mmrpc: RpcVersion.v2_0,
        currentBlock: currentBlock,
        fromId: cursorString,
        limit: limit,
        skipped: 0,
        syncStatus: SyncStatusResponse(
          state: TransactionSyncStatusEnum.finished,
        ),
        total: transactions.length,
        totalPages: 1,
        pageNumber: 1,
        pagingOptions: cursorString != null
            ? Pagination(fromId: cursorString)
            : null,
        transactions: transactions,
      );
    } catch (e) {
      throw HttpException('Error fetching TRONGrid transaction history: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Single-page fetch methods
  // ---------------------------------------------------------------------------

  /// Fetches up to [_maxInternalPages] TRONGrid pages of general transactions,
  /// filtering for `TransferContract` rows, until at least [limit] results are
  /// collected or there are no more pages.
  Future<_PageResult> _fetchTrxPage({
    required String host,
    required String address,
    required Asset asset,
    required int limit,
    String? fingerprint,
  }) async {
    final decimals = _decimals(asset);
    final out = <TransactionInfo>[];
    var cursor = fingerprint;

    for (var page = 0; page < _maxInternalPages; page++) {
      await _throttle();

      final params = <String, String>{
        'only_confirmed': 'true',
        'limit': '$_gridPageSize',
        'visible': 'true',
      };
      if (cursor != null) params['fingerprint'] = cursor;

      final uri = Uri.https(host, '/v1/accounts/$address/transactions', params);

      final json = await _getJson(uri);
      final data = json.valueOrNull<JsonList>('data') ?? const [];

      if (data.isEmpty) {
        cursor = null;
        break;
      }

      for (final row in data) {
        final tx = _gridTrxRowToTransactionInfo(
          row: row,
          viewerAddress: address,
          coinId: asset.id.id,
          decimals: decimals,
        );
        if (tx != null) out.add(tx);
      }

      final fp = _nextTronGridPageFingerprint(json);
      if (fp == null) {
        cursor = null;
        break;
      }
      cursor = fp;

      if (out.length >= limit) break;
    }

    return _PageResult(transactions: out, nextFingerprint: cursor);
  }

  /// Fetches a single TRONGrid page of TRC-20 transfers. Every row is relevant
  /// (no client-side type filtering), so one page is sufficient per call.
  Future<_PageResult> _fetchTrc20Page({
    required String host,
    required String address,
    required Asset asset,
    String? fingerprint,
  }) async {
    final contract = _trc20ContractAddress(asset);
    if (contract == null || contract.isEmpty) {
      return const _PageResult(transactions: []);
    }

    final decimals = _tokenDecimalsFromRowOrAsset(asset);

    await _throttle();

    final params = <String, String>{
      'only_confirmed': 'true',
      'limit': '$_gridPageSize',
      'contract_address': contract,
    };
    if (fingerprint != null) params['fingerprint'] = fingerprint;

    final uri = Uri.https(
      host,
      '/v1/accounts/$address/transactions/trc20',
      params,
    );

    final json = await _getJson(uri);
    final data = json.valueOrNull<JsonList>('data') ?? const [];
    if (data.isEmpty) {
      return const _PageResult(transactions: []);
    }

    final out = <TransactionInfo>[];
    for (final row in data) {
      final tx = _gridTrc20RowToTransactionInfo(
        row: row,
        viewerAddress: address,
        coinId: asset.id.id,
        decimals: decimals,
      );
      if (tx != null) out.add(tx);
    }

    final fp = _nextTronGridPageFingerprint(json);

    return _PageResult(transactions: out, nextFingerprint: fp);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Opaque TRONGrid `meta.fingerprint` token, or `null` when absent / empty.
  String? _nextTronGridPageFingerprint(JsonMap json) {
    final fp = json
        .valueOrNull<JsonMap>('meta')
        ?.valueOrNull<String>('fingerprint');
    if (fp == null || fp.isEmpty) return null;
    return fp;
  }

  Future<List<PubkeyInfo>> _getAssetPubkeys(Asset asset) async {
    return (await pubkeyManager.getPubkeys(asset)).keys;
  }

  String _defaultApiHost(ProtocolClass protocol) {
    return protocol.isTestnet ? 'nile.trongrid.io' : 'api.trongrid.io';
  }

  bool _looksLikeTransactionHash(String value) =>
      RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(value);

  int _decimals(Asset asset) =>
      asset.protocol.config.valueOrNull<int>('decimals') ?? 6;

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

  // ---------------------------------------------------------------------------
  // Row → TransactionInfo mappers
  // ---------------------------------------------------------------------------

  /// Maps a TRONGrid `/v1/accounts/.../transactions` row (fetched with
  /// `visible=true`) to [TransactionInfo]. Addresses are Base58 thanks to
  /// the visibility flag, consistent with the TRC-20 mapper.
  TransactionInfo? _gridTrxRowToTransactionInfo({
    required JsonMap row,
    required String viewerAddress,
    required String coinId,
    required int decimals,
  }) {
    final hash = row.valueOrNull<String>('txID');
    if (hash == null || hash.isEmpty) return null;

    final rawData = row.valueOrNull<JsonMap>('raw_data');
    final contracts = rawData?.valueOrNull<JsonList>('contract');
    if (contracts == null || contracts.isEmpty) return null;

    final first = contracts.first;
    final contractType = first.valueOrNull<String>('type');
    if (contractType != 'TransferContract') return null;

    final retList = row.valueOrNull<JsonList>('ret');
    final retMap = (retList != null && retList.isNotEmpty)
        ? retList.first as JsonMap?
        : null;
    final contractRet = retMap?.valueOrNull<String>('contractRet');
    if (contractRet != 'SUCCESS') return null;

    final value = first
        .valueOrNull<JsonMap>('parameter')
        ?.valueOrNull<JsonMap>('value');
    if (value == null) return null;

    final from = value.valueOrNull<String>('owner_address') ?? '';
    final to = value.valueOrNull<String>('to_address') ?? '';
    final amountRaw = value.valueOrNull<num>('amount');
    if (amountRaw == null) return null;

    final block = row.valueOrNull<int>('blockNumber') ?? 0;
    final tsMs = row.valueOrNull<int>('block_timestamp') ?? 0;
    final tsSec = tsMs ~/ 1000;

    final absHuman = fixedScaleIntToDecimalString(amountRaw.toInt(), decimals);

    final isOut = tronAddressesEqual(from, viewerAddress);
    final isIn = tronAddressesEqual(to, viewerAddress);
    if (!isOut && !isIn) return null;

    final (signedBalance, spentByMe, receivedByMe) = _classifyDirection(
      isOut: isOut,
      isIn: isIn,
      absHuman: absHuman,
    );

    return TransactionInfo(
      txHash: hash,
      from: [tronAddressForDisplay(from)],
      to: [tronAddressForDisplay(to)],
      myBalanceChange: signedBalance,
      blockHeight: block,
      confirmations: 1,
      timestamp: tsSec,
      feeDetails: null,
      coin: coinId,
      internalId: hash,
      spentByMe: spentByMe,
      receivedByMe: receivedByMe,
      memo: null,
    );
  }

  TransactionInfo? _gridTrc20RowToTransactionInfo({
    required JsonMap row,
    required String viewerAddress,
    required String coinId,
    required int decimals,
  }) {
    final hash = row.valueOrNull<String>('transaction_id');
    if (hash == null || hash.isEmpty) return null;

    final from = row.valueOrNull<String>('from') ?? '';
    final to = row.valueOrNull<String>('to') ?? '';
    final rawValue = row.valueOrNull<String>('value');
    if (rawValue == null || rawValue.isEmpty) return null;

    final tokenInfo = row.valueOrNull<JsonMap>('token_info');
    final dec = tokenInfo?.valueOrNull<int>('decimals') ?? decimals;

    final tsMs = row.valueOrNull<int>('block_timestamp') ?? 0;
    final tsSec = tsMs ~/ 1000;

    final absHuman = fixedScaleBigIntStringToDecimalString(rawValue, dec);

    final isOut = tronAddressesEqual(from, viewerAddress);
    final isIn = tronAddressesEqual(to, viewerAddress);
    if (!isOut && !isIn) return null;

    final (signedBalance, spentByMe, receivedByMe) = _classifyDirection(
      isOut: isOut,
      isIn: isIn,
      absHuman: absHuman,
    );

    return TransactionInfo(
      txHash: hash,
      from: [from],
      to: [to],
      myBalanceChange: signedBalance,
      blockHeight: 0,
      confirmations: 1,
      timestamp: tsSec,
      feeDetails: null,
      coin: coinId,
      internalId: hash,
      spentByMe: spentByMe,
      receivedByMe: receivedByMe,
      memo: null,
    );
  }

  // ---------------------------------------------------------------------------
  // Direction
  // ---------------------------------------------------------------------------

  (String signedBalance, String spentByMe, String receivedByMe)
  _classifyDirection({
    required bool isOut,
    required bool isIn,
    required String absHuman,
  }) {
    if (isOut && !isIn) return ('-$absHuman', absHuman, '0');
    if (isIn && !isOut) return (absHuman, '0', absHuman);
    return ('0', absHuman, absHuman);
  }

  // ---------------------------------------------------------------------------
  // Merge duplicates (same tx seen from multiple pubkeys)
  // ---------------------------------------------------------------------------

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

    return TransactionInfo(
      txHash: a.txHash,
      from: <String>{...a.from, ...b.from}.toList(),
      to: <String>{...a.to, ...b.to}.toList(),
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

  // ---------------------------------------------------------------------------
  // Rate limiter — keeps requests within TRONGrid's 3 RPS budget
  // ---------------------------------------------------------------------------

  Future<void> _throttle() async {
    final elapsed = DateTime.now().difference(_lastRequestTime);
    if (elapsed < _minRequestInterval) {
      await Future<void>.delayed(_minRequestInterval - elapsed);
    }
    _lastRequestTime = DateTime.now();
  }

  // ---------------------------------------------------------------------------
  // HTTP with retry & TRONGrid rate-limit parsing
  // ---------------------------------------------------------------------------

  Future<JsonMap> _getJson(Uri uri) async {
    final random = math.Random();
    var attempt = 0;
    var backoff = const Duration(milliseconds: 500);
    const maxBackoff = Duration(seconds: 10);

    while (true) {
      try {
        final response = await _client.get(uri);
        if (response.statusCode == 200) {
          return jsonFromString(response.body);
        }

        final retriable =
            response.statusCode == 429 || response.statusCode == 503;
        if (retriable && attempt < _maxHttpAttempts - 1) {
          final baseWait = _parseRetryWait(response) ?? backoff;
          final jitter = Duration(milliseconds: random.nextInt(250));
          await Future<void>.delayed(baseWait + jitter);
          _lastRequestTime = DateTime.now();
          attempt++;
          final doubled = backoff.inMilliseconds * 2;
          backoff = doubled > maxBackoff.inMilliseconds
              ? maxBackoff
              : Duration(milliseconds: doubled);
          continue;
        }

        throw HttpException(
          'TRONGrid request failed: ${response.statusCode}',
          uri: uri,
        );
      } on http.ClientException catch (e) {
        if (attempt >= _maxHttpAttempts - 1) {
          throw HttpException(
            'Network error while fetching TRONGrid history: ${e.message}',
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

  /// Extracts the wait duration from a TRONGrid rate-limit response.
  ///
  /// Checks the `Retry-After` header first, then falls back to parsing the
  /// JSON body for the `"suspended for N s"` pattern that TRONGrid returns.
  Duration? _parseRetryWait(http.Response response) {
    final header = response.headers['retry-after'];
    if (header != null) {
      final seconds = int.tryParse(header.trim());
      if (seconds != null) {
        return Duration(seconds: seconds.clamp(0, 60));
      }
    }

    try {
      final body = jsonFromString(response.body);
      final error = body.valueOrNull<String>('Error') ?? '';
      final match = RegExp(r'suspended for (\d+) s').firstMatch(error);
      if (match != null) {
        final seconds = int.parse(match.group(1)!);
        return Duration(seconds: seconds.clamp(0, 60));
      }
    } on FormatException catch (_) {
      // Body is not valid JSON; fall through to return null.
    }

    return null;
  }

  /// Releases the HTTP client if it was internally created.
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

/// Result of a single page fetch from TRONGrid.
class _PageResult {
  const _PageResult({required this.transactions, this.nextFingerprint});
  final List<TransactionInfo> transactions;
  final String? nextFingerprint;
}
