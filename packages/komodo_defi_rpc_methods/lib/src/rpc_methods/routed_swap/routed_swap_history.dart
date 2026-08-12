/// PROVISIONAL — `routed_swap::history` has no published response schema.
///
/// §7 of the contract specifies this method in one prose sentence ("expose
/// routed-specific current/terminal details") with no example payload, while
/// §2, §4, §5 and §7 all route mandatory behaviour through it: post-restart
/// recovery, cancellation confirmation, and the only routed history view.
///
/// Everything in this file is therefore the shape the GUI team proposed in
/// review, not a ratified contract. It is isolated in its own file so that
/// when §7 lands there is exactly one place to change, and the
/// `komodo_defi_harness` fixture emits the matching shape with its invented
/// fields listed in `RoutedSwapFixture.provisionalHistoryKeys`.
///
/// Do not build a shipping history screen on this until §7 is published.
library;

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Which records to return.
enum RoutedSwapHistoryFilter {
  /// Everything. The default, and the only safe default — a filter that
  /// defaulted to one subset would silently drop data from existing callers.
  all('all'),

  /// Swaps that have not reached a terminal state. Drives the cold-start
  /// "you have a swap in flight" banner after an app restart.
  inFlight('in_flight'),

  /// Swaps that have finished, successfully or not.
  terminal('terminal');

  const RoutedSwapHistoryFilter(this.wire);

  /// The wire value.
  final String wire;
}

/// PROVISIONAL. `routed_swap::history` — the durable routed-swap record.
class RoutedSwapHistoryRequest
    extends BaseRequest<RoutedSwapHistoryResponse, GeneralErrorResponse> {
  RoutedSwapHistoryRequest({
    required super.rpcPass,
    this.limit = 20,
    this.pageNumber = 1,
    this.uuid,
    this.filter,
  }) : super(method: 'routed_swap::history', mmrpc: RpcVersion.v2_0);

  /// Page size.
  final int limit;

  /// 1-based page number.
  final int pageNumber;

  /// Fetch a single record. The recovery path: after a restart the GUI holds a
  /// uuid and no task id, and paging to find one known swap is wasteful.
  final String? uuid;

  /// Restrict to in-flight or terminal records.
  final RoutedSwapHistoryFilter? filter;

  @override
  JsonMap toJson() => {
    ...super.toJson(),
    'params': {
      'limit': limit,
      'page_number': pageNumber,
      if (uuid != null) 'uuid': uuid,
      if (filter != null) 'status_filter': filter!.wire,
    },
  };

  @override
  RoutedSwapHistoryResponse parse(JsonMap json) =>
      RoutedSwapHistoryResponse.parse(json);
}

/// PROVISIONAL. A page of routed-swap records.
class RoutedSwapHistoryResponse extends BaseResponse {
  RoutedSwapHistoryResponse({
    required super.mmrpc,
    required this.entries,
    required this.total,
    required this.limit,
    required this.pageNumber,
  });

  /// Parses the proposed `result.{entries, total, limit, page_number}`.
  factory RoutedSwapHistoryResponse.parse(JsonMap json) {
    final result = json.value<JsonMap>('result');
    return RoutedSwapHistoryResponse(
      mmrpc: json.value<String>('mmrpc'),
      entries: (result.valueOrNull<List<dynamic>>('entries') ?? const [])
          .map((e) => RoutedSwapHistoryEntry.fromJson(e as JsonMap))
          .toList(),
      total: result.valueOrNull<int>('total') ?? 0,
      limit: result.valueOrNull<int>('limit') ?? 0,
      pageNumber: result.valueOrNull<int>('page_number') ?? 1,
    );
  }

  /// Records on this page, newest first.
  final List<RoutedSwapHistoryEntry> entries;

  /// Total matching records across all pages.
  final int total;

  /// Echoed page size.
  final int limit;

  /// Echoed page number.
  final int pageNumber;

  @override
  JsonMap toJson() => {
    'mmrpc': mmrpc,
    'result': {
      'entries': entries.length,
      'total': total,
      'limit': limit,
      'page_number': pageNumber,
    },
  };
}

/// PROVISIONAL. One persisted routed swap.
class RoutedSwapHistoryEntry {
  const RoutedSwapHistoryEntry({
    required this.uuid,
    required this.provider,
    required this.status,
    required this.sent,
    required this.createdAt,
    required this.updatedAt,
    this.state,
    this.kind,
    this.received,
    this.outcome,
    this.errorType,
    this.errorData,
    this.approveTxHash,
    this.sourceTxHash,
    this.destTxHash,
    this.finishedAt,
  });

  /// Parses one proposed `entries[]` record.
  factory RoutedSwapHistoryEntry.fromJson(JsonMap json) {
    final outcome = json.valueOrNull<String>('outcome');
    final received = json.valueOrNull<JsonMap>('received');
    final sent =
        json.valueOrNull<JsonMap>('sent') ?? json.value<JsonMap>('from');
    return RoutedSwapHistoryEntry(
      uuid: json.value<String>('uuid'),
      provider: json.value<String>('provider'),
      status: json.value<String>('status'),
      state: json.valueOrNull<String>('state'),
      kind: json.valueOrNull<String>('kind') == null
          ? null
          : RoutedSwapRouteKind.parse(json.value<String>('kind')),
      sent: RoutedSwapAmount.fromJson(sent),
      received: received == null ? null : RoutedSwapAmount.fromJson(received),
      outcome: outcome == null ? null : RoutedSwapOutcome.parse(outcome),
      errorType: json.valueOrNull<String>('error_type'),
      errorData: json.valueOrNull<JsonMap>('error_data'),
      approveTxHash: json.valueOrNull<String>('approve_tx_hash'),
      sourceTxHash: json.valueOrNull<String>('source_tx_hash'),
      destTxHash: json.valueOrNull<String>('dest_tx_hash'),
      createdAt: json.valueOrNull<int>('created_at') ?? 0,
      updatedAt: json.valueOrNull<int>('updated_at') ?? 0,
      finishedAt: json.valueOrNull<int>('finished_at'),
    );
  }

  /// The persistent swap id — the only handle that survives a restart.
  final String uuid;

  /// Echoed provider.
  final String provider;

  /// `InProgress`, `Ok` or `Error`.
  final String status;

  /// Last observed in-progress state, when still running.
  final String? state;

  /// Same-chain or cross-chain.
  final RoutedSwapRouteKind? kind;

  /// What the user sent. Without this a GUI that lost the task cannot join a
  /// history record back to the swap it started.
  final RoutedSwapAmount sent;

  /// What the user received, once terminal.
  final RoutedSwapAmount? received;

  /// Terminal outcome, when the swap ended `Ok`.
  final RoutedSwapOutcome? outcome;

  /// Terminal error type.
  ///
  /// Two values are reachable **only** here and never from `status`:
  /// `TaskCancelled` and `AbortedOnRestart`. In both cases the task id is gone,
  /// so a status lookup answers `NoSuchTask`.
  final String? errorType;

  /// Terminal error payload.
  final JsonMap? errorData;

  /// Approval transaction, when one was sent.
  final String? approveTxHash;

  /// Source-chain transaction.
  final String? sourceTxHash;

  /// Destination-chain transaction.
  final String? destTxHash;

  /// Creation timestamp. Immutable, so paging stays stable while an in-flight
  /// record mutates underneath it.
  final int createdAt;

  /// Last update timestamp.
  final int updatedAt;

  /// Completion timestamp, when terminal.
  final int? finishedAt;

  /// Whether this swap is still running and should be resumed on cold start.
  bool get isInFlight => status == 'InProgress';

  /// Whether the record shows a swap that consumed gas without swapping.
  ///
  /// Both cases are only ever visible here, and both mean the user paid for
  /// nothing — worth surfacing rather than rendering as a neutral "cancelled".
  bool get spentGasWithoutSwapping =>
      approveTxHash != null &&
      (errorType == 'TaskCancelled' || errorType == 'AbortedOnRestart');
}
