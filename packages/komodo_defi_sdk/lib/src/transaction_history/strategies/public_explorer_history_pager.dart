import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Converts a non-JSON legacy cursor into a provider cursor value.
///
/// Return `null` when the bare cursor should be ignored.
typedef PublicExplorerBareCursorDecoder = Object? Function(String cursor);

/// Parses provider-specific retry delays from a throttled HTTP response.
typedef PublicExplorerRetryWaitParser =
    Duration? Function(http.Response response);

/// Shared per-address pagination helper for public transaction explorers.
///
/// The strategies keep provider-specific endpoint and row mapping code. This
/// helper only owns opaque cursor bookkeeping so each UI-visible fetch advances
/// at most one selected address and can resume without refetching exhausted
/// addresses.
class PublicExplorerHistoryPager {
  /// Creates a pager with a cap for filtered-empty provider pages.
  const PublicExplorerHistoryPager({this.maxEmptyPagesPerAddress = 3});

  /// Cursor marker for addresses queued but not fetched yet.
  static const String pendingCursorMarker = '__pending__';

  static const String _cursorWrapperKey = '__cursor__';
  static const String _emptyPagesKey = '__empty_pages__';

  /// Maximum consecutive provider pages with no locally usable transactions
  /// before an address is treated as exhausted.
  final int maxEmptyPagesPerAddress;

  /// Decodes an opaque cursor string into address-scoped cursor entries.
  Map<String, PublicExplorerCursorEntry> decodeCursorMap(
    String fromId, {
    PublicExplorerBareCursorDecoder? decodeBareCursor,
  }) {
    if (fromId.isEmpty) return const {};

    if (!fromId.trimLeft().startsWith('{')) {
      final cursor = decodeBareCursor?.call(fromId);
      return cursor == null
          ? const {}
          : {'': PublicExplorerCursorEntry.cursor(cursor)};
    }

    try {
      final decoded = jsonDecode(fromId);
      if (decoded is! Map) return const {};

      return decoded.map((key, value) {
        return MapEntry('$key', _decodeCursorEntry(value));
      });
    } on FormatException {
      return const {};
    }
  }

  /// Selects the next address and provider cursor to fetch.
  PublicExplorerAddressPage? selectAddressPage(
    List<String> addresses,
    Map<String, PublicExplorerCursorEntry> cursors,
  ) {
    if (addresses.isEmpty) return null;
    if (cursors.isEmpty) {
      return PublicExplorerAddressPage(address: addresses.first);
    }

    for (final address in addresses) {
      final cursor = cursors[address] ?? cursors[''];
      if (cursor == null) continue;
      return PublicExplorerAddressPage(
        address: address,
        cursor: cursor.isPending ? null : cursor.value,
      );
    }

    return null;
  }

  /// Builds the next opaque cursor map after one provider page is fetched.
  Map<String, PublicExplorerCursorEntry> nextCursorMap({
    required List<String> addresses,
    required Map<String, PublicExplorerCursorEntry> currentCursors,
    required String? selectedAddress,
    required Object? nextCursor,
    required bool pageProducedTransactions,
  }) {
    if (selectedAddress == null) return const {};

    final next = <String, PublicExplorerCursorEntry>{};
    final selectedCurrent =
        currentCursors[selectedAddress] ?? currentCursors[''];

    if (nextCursor != null) {
      final currentEmptyPages = selectedCurrent?.emptyPages ?? 0;
      final nextEmptyPages = pageProducedTransactions
          ? 0
          : currentEmptyPages + 1;

      if (nextEmptyPages <= maxEmptyPagesPerAddress) {
        next[selectedAddress] = PublicExplorerCursorEntry.cursor(
          nextCursor,
          emptyPages: nextEmptyPages,
        );
      }
    }

    final validAddresses = addresses.toSet();
    for (final entry in currentCursors.entries) {
      if (entry.key == selectedAddress || entry.key.isEmpty) continue;
      if (validAddresses.contains(entry.key)) {
        next[entry.key] = entry.value;
      }
    }

    if (currentCursors.isEmpty) {
      var afterSelected = false;
      for (final address in addresses) {
        if (address == selectedAddress) {
          afterSelected = true;
          continue;
        }
        if (afterSelected) {
          next.putIfAbsent(address, PublicExplorerCursorEntry.pending);
        }
      }
    }

    return next;
  }

  /// Encodes cursor entries into the public opaque `fromId` string.
  String? encodeCursorMap(Map<String, PublicExplorerCursorEntry> cursors) {
    if (cursors.isEmpty) return null;

    return jsonEncode({
      for (final entry in cursors.entries) entry.key: entry.value.toJson(),
    });
  }

  /// Builds the KDF-style transaction history response from one provider page.
  MyTxHistoryResponse buildResponse({
    required List<TransactionInfo> transactions,
    required Map<String, PublicExplorerCursorEntry> nextCursors,
    required int limit,
    int? pageNumber,
    int? currentBlock,
  }) {
    final cursorString = encodeCursorMap(nextCursors);
    final resolvedBlock =
        currentBlock ??
        transactions.fold<int>(
          0,
          (maxBlock, tx) =>
              tx.blockHeight > maxBlock ? tx.blockHeight : maxBlock,
        );

    return MyTxHistoryResponse(
      mmrpc: RpcVersion.v2_0,
      currentBlock: resolvedBlock,
      fromId: cursorString,
      limit: limit,
      skipped: 0,
      syncStatus: SyncStatusResponse(state: TransactionSyncStatusEnum.finished),
      total: transactions.length,
      totalPages: 1,
      pageNumber: pageNumber,
      pagingOptions: cursorString == null
          ? null
          : Pagination(fromId: cursorString),
      transactions: transactions,
    );
  }

  PublicExplorerCursorEntry _decodeCursorEntry(dynamic value) {
    if (_isPendingCursor(value)) {
      return const PublicExplorerCursorEntry.pending();
    }

    if (value is Map<Object?, Object?>) {
      final normalized = _jsonMap(value);
      if (normalized.containsKey(_cursorWrapperKey)) {
        return PublicExplorerCursorEntry.cursor(
          normalized[_cursorWrapperKey],
          emptyPages: _intFrom(normalized[_emptyPagesKey]) ?? 0,
        );
      }
      return PublicExplorerCursorEntry.cursor(normalized);
    }

    return PublicExplorerCursorEntry.cursor(value);
  }

  bool _isPendingCursor(dynamic value) {
    if (value == pendingCursorMarker) return true;
    if (value is Map<Object?, Object?>) {
      return value[pendingCursorMarker] == true || value['pending'] == true;
    }
    return false;
  }

  JsonMap _jsonMap(Map<Object?, Object?> value) {
    return value.map((key, entryValue) => MapEntry('$key', entryValue));
  }

  int? _intFrom(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

/// Address and provider cursor selected for the next explorer request.
class PublicExplorerAddressPage {
  /// Creates an address page selection.
  const PublicExplorerAddressPage({required this.address, this.cursor});

  /// Wallet address to query.
  final String address;

  /// Provider-specific cursor value, or `null` for a first page.
  final Object? cursor;
}

/// One address-scoped opaque cursor entry.
class PublicExplorerCursorEntry {
  const PublicExplorerCursorEntry._({
    required this.value,
    required this.isPending,
    required this.emptyPages,
  });

  /// Creates an entry for a queued address that has not been fetched yet.
  const PublicExplorerCursorEntry.pending()
    : this._(value: null, isPending: true, emptyPages: 0);

  /// Creates an entry with a provider-specific cursor value.
  const PublicExplorerCursorEntry.cursor(Object? value, {int emptyPages = 0})
    : this._(value: value, isPending: false, emptyPages: emptyPages);

  /// Provider cursor value.
  final Object? value;

  /// Whether this entry marks a not-yet-started address.
  final bool isPending;

  /// Consecutive provider pages with no locally usable transactions.
  final int emptyPages;

  /// Encodes this entry while preserving legacy simple cursor shapes.
  Object? toJson() {
    if (isPending) return PublicExplorerHistoryPager.pendingCursorMarker;
    if (emptyPages <= 0) return value;
    return {
      PublicExplorerHistoryPager._cursorWrapperKey: value,
      PublicExplorerHistoryPager._emptyPagesKey: emptyPages,
    };
  }
}

/// Retry and throttling policy for constrained public explorer APIs.
class PublicExplorerHttpRetryPolicy {
  /// Creates a retry policy for a public transaction explorer.
  const PublicExplorerHttpRetryPolicy({
    required this.failureLabel,
    required this.networkFailureLabel,
    this.minRequestInterval = Duration.zero,
    this.maxAttempts = 1,
    this.initialBackoff = const Duration(milliseconds: 500),
    this.maxBackoff = const Duration(seconds: 10),
    this.jitter = Duration.zero,
    this.retryStatusCodes = const {429, 503},
    this.retryWaitParser,
  });

  /// Minimum gap between HTTP requests.
  final Duration minRequestInterval;

  /// Maximum request attempts, including the first attempt.
  final int maxAttempts;

  /// Initial exponential backoff when no explicit retry delay is available.
  final Duration initialBackoff;

  /// Maximum exponential backoff.
  final Duration maxBackoff;

  /// Random jitter upper bound added to retry delays.
  final Duration jitter;

  /// HTTP status codes that can be retried.
  final Set<int> retryStatusCodes;

  /// Provider-specific retry delay parser.
  final PublicExplorerRetryWaitParser? retryWaitParser;

  /// Error label for non-success HTTP responses.
  final String failureLabel;

  /// Error label for transport failures.
  final String networkFailureLabel;
}

/// Small JSON HTTP client with public-explorer throttling and bounded retry.
class PublicExplorerJsonHttpClient {
  /// Creates a JSON client around an injected [http.Client].
  PublicExplorerJsonHttpClient({
    required http.Client client,
    required PublicExplorerHttpRetryPolicy policy,
    bool ownsClient = false,
    math.Random? random,
  }) : _client = client,
       _policy = policy,
       _ownsClient = ownsClient,
       _random = random ?? math.Random();

  final http.Client _client;
  final PublicExplorerHttpRetryPolicy _policy;
  final bool _ownsClient;
  final math.Random _random;
  DateTime _lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Fetches and decodes a JSON object from [uri].
  Future<JsonMap> getJson(Uri uri) async {
    var attempt = 0;
    var backoff = _policy.initialBackoff;

    while (true) {
      await _throttle();

      try {
        final response = await _client.get(uri);
        if (response.statusCode == 200) {
          return jsonFromString(response.body);
        }

        if (_canRetry(response.statusCode, attempt)) {
          await _delayBeforeRetry(response, backoff);
          attempt++;
          backoff = _nextBackoff(backoff);
          continue;
        }

        throw HttpException(
          '${_policy.failureLabel}: ${response.statusCode}',
          uri: uri,
        );
      } on http.ClientException catch (e) {
        if (attempt >= _policy.maxAttempts - 1) {
          throw HttpException(
            '${_policy.networkFailureLabel}: ${e.message}',
            uri: uri,
          );
        }

        await _delay(backoff);
        attempt++;
        backoff = _nextBackoff(backoff);
      }
    }
  }

  /// Extracts a standard `Retry-After` delay from an HTTP response.
  static Duration? retryAfterHeaderWait(http.Response response) {
    final header = response.headers['retry-after'];
    if (header == null) return null;

    final seconds = int.tryParse(header.trim());
    if (seconds != null) {
      return Duration(seconds: seconds.clamp(0, 60));
    }

    return null;
  }

  /// Closes the owned HTTP client, if any.
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  bool _canRetry(int statusCode, int attempt) {
    return _policy.retryStatusCodes.contains(statusCode) &&
        attempt < _policy.maxAttempts - 1;
  }

  Future<void> _throttle() async {
    final minInterval = _policy.minRequestInterval;
    if (minInterval.inMicroseconds <= 0) return;

    final elapsed = DateTime.now().difference(_lastRequestTime);
    if (elapsed < minInterval) {
      await Future<void>.delayed(minInterval - elapsed);
    }
    _lastRequestTime = DateTime.now();
  }

  Future<void> _delayBeforeRetry(
    http.Response response,
    Duration fallback,
  ) async {
    final wait =
        _policy.retryWaitParser?.call(response) ??
        retryAfterHeaderWait(response) ??
        fallback;
    await _delay(wait);
  }

  Future<void> _delay(Duration baseWait) async {
    final jitter = _policy.jitter.inMilliseconds <= 0
        ? Duration.zero
        : Duration(
            milliseconds: _random.nextInt(_policy.jitter.inMilliseconds),
          );
    await Future<void>.delayed(baseWait + jitter);
    _lastRequestTime = DateTime.now();
  }

  Duration _nextBackoff(Duration current) {
    final doubled = current.inMilliseconds * 2;
    return doubled > _policy.maxBackoff.inMilliseconds
        ? _policy.maxBackoff
        : Duration(milliseconds: doubled);
  }
}
