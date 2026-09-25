import 'package:equatable/equatable.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Which records `routed_swap::history` returns.
enum RoutedSwapHistoryFilter {
  /// Everything. The KDF default.
  all('all'),

  /// Swaps that have not reached a terminal state. Drives resume after a
  /// restart.
  inFlight('in_flight'),

  /// Swaps that have finished, successfully or not.
  terminal('terminal');

  const RoutedSwapHistoryFilter(this.wire);

  /// The wire value.
  final String wire;
}

/// `routed_swap::history` — every routed swap, in-flight and finished, kept
/// across restarts. The recovery surface: after a restart `task_id`s are gone
/// and a swap is recovered here by its `uuid`.
///
/// Every parameter is optional and omitted when null, so the engine's own
/// defaults apply (`status_filter: all`, `limit: 10`, `page_number: 1`).
class RoutedSwapHistoryRequest
    extends RoutedSwapRequestBase<RoutedSwapHistoryResponse> {
  RoutedSwapHistoryRequest({
    required super.rpcPass,
    this.uuid,
    this.filter,
    this.myCoin,
    this.otherCoin,
    this.fromTimestamp,
    this.toTimestamp,
    this.limit,
    this.pageNumber,
  }) : super(method: 'routed_swap::history');

  /// Exact-match lookup for one swap.
  final String? uuid;

  /// Restrict to in-flight or terminal records.
  final RoutedSwapHistoryFilter? filter;

  /// Source ticker.
  final String? myCoin;

  /// Destination ticker.
  final String? otherCoin;

  /// Lower bound on `created_at`, unix seconds.
  final int? fromTimestamp;

  /// Upper bound on `created_at`, unix seconds.
  final int? toTimestamp;

  /// Page size. KDF defaults to 10.
  final int? limit;

  /// 1-based page number.
  final int? pageNumber;

  @override
  JsonMap toJson() => {
    ...super.toJson(),
    'params': {
      if (uuid != null) 'uuid': uuid,
      if (filter != null) 'status_filter': filter!.wire,
      if (myCoin != null) 'my_coin': myCoin,
      if (otherCoin != null) 'other_coin': otherCoin,
      if (fromTimestamp != null) 'from_timestamp': fromTimestamp,
      if (toTimestamp != null) 'to_timestamp': toTimestamp,
      if (limit != null) 'limit': limit,
      if (pageNumber != null) 'page_number': pageNumber,
    },
  };

  @override
  RoutedSwapHistoryResponse parse(JsonMap json) =>
      RoutedSwapHistoryResponse.parse(json);
}

/// A page of routed-swap records.
class RoutedSwapHistoryResponse extends BaseResponse {
  RoutedSwapHistoryResponse({
    required super.mmrpc,
    required this.entries,
    required this.total,
    required this.limit,
    required this.pageNumber,
    required this.totalPages,
  });

  /// Parses `result.{entries, total, limit, page_number, total_pages}`.
  ///
  /// An entry that fails to parse is dropped rather than failing the page, the
  /// same way KDF skips an unreadable row: one malformed record must not hide
  /// every other swap.
  factory RoutedSwapHistoryResponse.parse(JsonMap json) {
    final result = json.value<JsonMap>('result');
    final entries = <RoutedSwapHistoryEntry>[];
    for (final raw
        in result.valueOrNull<List<dynamic>>('entries') ?? const []) {
      if (raw is! Map) continue;
      try {
        entries.add(RoutedSwapHistoryEntry.fromJson(convertToJsonMap(raw)));
      } on Object {
        // Skipped; see above.
      }
    }
    return RoutedSwapHistoryResponse(
      mmrpc: json.valueOrNull<String>('mmrpc') ?? '2.0',
      entries: entries,
      total: result.valueOrNull<int>('total') ?? entries.length,
      limit: result.valueOrNull<int>('limit') ?? entries.length,
      pageNumber: result.valueOrNull<int>('page_number') ?? 1,
      totalPages: result.valueOrNull<int>('total_pages') ?? 1,
    );
  }

  /// Records on this page, newest first on `created_at`.
  final List<RoutedSwapHistoryEntry> entries;

  /// Total matching records across all pages.
  final int total;

  /// Echoed page size.
  final int limit;

  /// Echoed page number.
  final int pageNumber;

  /// How many pages match.
  final int totalPages;

  /// Whether a later page exists.
  bool get hasMore => pageNumber < totalPages;

  @override
  JsonMap toJson() => {
    'mmrpc': mmrpc,
    'result': {
      'entries': entries.length,
      'total': total,
      'limit': limit,
      'page_number': pageNumber,
      'total_pages': totalPages,
    },
  };
}

/// The request side accepted at `init`, kept so the original request is
/// identifiable without a retained `task_id` — including for swaps that ended
/// before any route was executed.
///
/// This is what was *requested*, not what moved: an `AbortedOnRestart` entry
/// still carries it although nothing was sent.
class RoutedSwapRequested extends Equatable {
  const RoutedSwapRequested({
    required this.from,
    required this.to,
    required this.amount,
  });

  /// Parses `{from, to, amount}`.
  factory RoutedSwapRequested.fromJson(JsonMap json) => RoutedSwapRequested(
    from: json.value<String>('from'),
    to: json.value<String>('to'),
    amount: json.value<String>('amount'),
  );

  /// Source ticker.
  final String from;

  /// Destination ticker.
  final String to;

  /// Requested sell amount, in coin units.
  final String amount;

  @override
  List<Object?> get props => [from, to, amount];
}

/// Actual gas paid by one transaction.
class RoutedSwapGasSpent extends Equatable {
  const RoutedSwapGasSpent({
    required this.txHash,
    required this.coin,
    required this.amount,
  });

  /// Parses `{tx_hash, coin, amount}`.
  factory RoutedSwapGasSpent.fromJson(JsonMap json) => RoutedSwapGasSpent(
    txHash: json.valueOrNull<String>('tx_hash') ?? '',
    coin: json.value<String>('coin'),
    amount: json.value<String>('amount'),
  );

  /// The transaction that paid it.
  final String txHash;

  /// The native coin it was paid in.
  final String coin;

  /// How much, in coin units.
  final String amount;

  @override
  List<Object?> get props => [txHash, coin, amount];
}

/// Total actual gas paid in one native coin.
class RoutedSwapGasTotal extends Equatable {
  const RoutedSwapGasTotal({required this.coin, required this.amount});

  /// Parses `{coin, amount}`.
  factory RoutedSwapGasTotal.fromJson(JsonMap json) => RoutedSwapGasTotal(
    coin: json.value<String>('coin'),
    amount: json.value<String>('amount'),
  );

  /// The native coin.
  final String coin;

  /// How much, in coin units.
  final String amount;

  @override
  List<Object?> get props => [coin, amount];
}

/// One persisted routed swap: the envelope plus [swap], which is exactly the
/// `task::routed_swap::status` result — one shape for a running swap and a
/// stored one. Two outcomes are reachable only here, because the task they
/// belonged to no longer exists: `TaskCancelled` and `AbortedOnRestart`.
class RoutedSwapHistoryEntry extends Equatable {
  const RoutedSwapHistoryEntry({
    required this.createdAt,
    required this.updatedAt,
    required this.requested,
    required this.minToAmountAccepted,
    required this.approvalTxHashes,
    required this.gasSpent,
    required this.totalGasSpent,
    required this.swap,
    this.finishedAt,
  });

  /// Parses one `entries[]` record.
  factory RoutedSwapHistoryEntry.fromJson(JsonMap json) {
    final swap = json.value<JsonMap>('swap');
    return RoutedSwapHistoryEntry(
      createdAt: json.valueOrNull<int>('created_at') ?? 0,
      updatedAt: json.valueOrNull<int>('updated_at') ?? 0,
      finishedAt: json.valueOrNull<int>('finished_at'),
      requested: RoutedSwapRequested.fromJson(json.value<JsonMap>('requested')),
      minToAmountAccepted:
          json.valueOrNull<String>('min_to_amount_accepted') ?? '0',
      approvalTxHashes: [
        for (final hash
            in json.valueOrNull<List<dynamic>>('approval_tx_hashes') ??
                const [])
          if (hash is String) hash,
      ],
      gasSpent: [
        for (final raw
            in json.valueOrNull<List<dynamic>>('gas_spent') ?? const [])
          if (raw is Map) RoutedSwapGasSpent.fromJson(convertToJsonMap(raw)),
      ],
      totalGasSpent: [
        for (final raw
            in json.valueOrNull<List<dynamic>>('total_gas_spent') ?? const [])
          if (raw is Map) RoutedSwapGasTotal.fromJson(convertToJsonMap(raw)),
      ],
      swap: RoutedSwapStatus.parse(
        swap.value<String>('status'),
        swap.value<JsonMap>('details'),
      ),
    );
  }

  /// Unix seconds, immutable — page contents stay stable while in-flight
  /// entries mutate.
  final int createdAt;

  /// Unix seconds of the last change.
  final int updatedAt;

  /// Unix seconds, present only on terminal entries.
  final int? finishedAt;

  /// The request side the user accepted at `init`.
  final RoutedSwapRequested requested;

  /// The guaranteed minimum the user accepted at `init`.
  final String minToAmountAccepted;

  /// Every approval broadcast, in order. Empty when none. May grow after a
  /// cancellation when an approval already in flight returns its hash.
  final List<String> approvalTxHashes;

  /// Actual gas paid per transaction.
  final List<RoutedSwapGasSpent> gasSpent;

  /// Actual gas paid per native coin.
  final List<RoutedSwapGasTotal> totalGasSpent;

  /// The status result for this swap.
  final RoutedSwapStatus swap;

  /// The persistent swap id.
  String get uuid => swap.uuid;

  /// Echoed provider.
  String get provider => swap.provider;

  /// Whether the swap is still running and should be resumed.
  bool get isInFlight => swap is RoutedSwapInProgress;

  @override
  List<Object?> get props => [
    createdAt,
    updatedAt,
    finishedAt,
    requested,
    minToAmountAccepted,
    approvalTxHashes,
    gasSpent,
    totalGasSpent,
    swap,
  ];
}
