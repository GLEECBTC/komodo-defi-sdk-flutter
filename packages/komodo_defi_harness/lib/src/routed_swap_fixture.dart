import 'package:komodo_defi_harness/src/kdf_script.dart';

/// Scripts the `routed_swap` RPC surface onto a [KdfScript].
///
/// Built against `GLEECBTC/gleec-specs` PR #2 — *Routed Swap API Contract
/// (LI.FI)*, revision 1. KDF does not implement this contract yet, which is
/// exactly why the fixture exists: a routed swap runs against a live bridge
/// with real money and takes 30+ minutes, so it is not a dev loop. Everything
/// the GUI needs to render — the whole in-progress ladder, every terminal
/// error, restart, cancellation, and a forgotten task — has to be reachable in
/// milliseconds and on demand.
///
/// **One section is not ratified.** §7 `routed_swap::history` ships with no
/// response schema, only the prose "expose routed-specific current/terminal
/// details". [historyEntries] therefore emits the shape the GUI team proposed
/// in review, and every field it invents is listed in
/// [provisionalHistoryKeys].
/// When §7 lands, fix this file first: the tests that fail are precisely the
/// assumptions the contract had not pinned down.
///
/// Composes with `KdfWalletFixture` rather than replacing it — call
/// [applyTo] on the script that fixture builds, so a test can sign in,
/// activate coins and then swap.
class RoutedSwapFixture {
  /// Creates a fixture that echoes [provider] on every provider-bearing
  /// response.
  RoutedSwapFixture({this.provider = 'lifi'});

  /// Echoed on every provider-bearing response and persisted record. `lifi` is
  /// the only v1 value; the field exists so a second aggregator does not force
  /// a rename of everything the GUI codes against.
  final String provider;

  final Map<String, int> _supportedCoins = <String, int>{};
  final Map<String, RoutedSwapQuote> _quotes = <String, RoutedSwapQuote>{};
  final Map<String, RoutedSwapQuoteError> _quoteErrors =
      <String, RoutedSwapQuoteError>{};
  final List<RoutedSwapRun> _pendingRuns = <RoutedSwapRun>[];

  final Map<int, _RoutedTask> _tasks = <int, _RoutedTask>{};
  final List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];

  int _nextTaskId = 1;
  int _nextUuid = 1;
  int _clock = 1754784000;

  /// Fields [historyEntries] emits that §7 does not specify. Asserting against
  /// this set is how a test says "this expectation rests on an unratified
  /// guess" out loud instead of silently freezing it.
  static const Set<String> provisionalHistoryKeys = _provisionalHistoryKeys;
  static const Set<String> _provisionalHistoryKeys = <String>{
    'created_at',
    'updated_at',
    'finished_at',
    'min_to_amount',
    'sent',
    'gas_spent',
    'approval_tx_hashes',
  };

  /// Marks [coin] eligible to *attempt* a quote. Per §6 this is not a promise
  /// that a route exists — the GUI must still call `routed_swap::quote`, and
  /// scripting a coin here while scripting no quote for the pair is the honest
  /// way to reproduce that.
  void supportedCoin(String coin, {required int chainId}) {
    _supportedCoins[coin] = chainId;
  }

  /// Scripts a successful `routed_swap::quote` for the `from`/`to` pair.
  void quote(RoutedSwapQuote quote) {
    _quotes[_pairKey(quote.from, quote.to)] = quote;
  }

  /// Scripts `routed_swap::quote` failing for a pair.
  ///
  /// All seven §1 error types are reachable; [RoutedSwapQuoteError] carries the
  /// documented `error_data` for each.
  void quoteFails(String from, String to, RoutedSwapQuoteError error) {
    _quoteErrors[_pairKey(from, to)] = error;
  }

  /// Enqueues one execution. `task::routed_swap::init` pops the next run in
  /// order, so a test can script a `QuoteWorsened` rejection followed by the
  /// successful retry — the exact sequence the "price changed" dialog drives.
  void run(RoutedSwapRun run) => _pendingRuns.add(run);

  /// Drops every in-memory task the way a KDF restart does.
  ///
  /// Tasks that had not reached [RoutedSwapState.broadcasting] become
  /// `AbortedOnRestart` in persistent history; tasks past it keep tracking and
  /// stay queryable by `uuid`. Task ids never survive — a later status lookup
  /// on a retained id is `NoSuchTask`, which is the whole reason the GUI must
  /// recover through history.
  void restartKdf() {
    for (final task in _tasks.values) {
      if (task.hasBroadcast) {
        // Persisted tracking resumes; the record is already in history and
        // keeps its state.
        continue;
      }
      _writeHistory(
        task,
        status: 'Error',
        errorType: 'AbortedOnRestart',
        finished: true,
      );
    }
    _tasks.clear();
  }

  /// Wires every scripted method onto [script].
  void applyTo(KdfScript script) {
    script
      ..on('routed_swap::supported_coins', (_) => _supportedCoinsResponse())
      ..on('routed_swap::quote', _quoteResponse)
      ..on('routed_swap::history', _historyResponse)
      ..on('task::routed_swap::init', _initResponse)
      ..on('task::routed_swap::status', _statusResponse)
      ..on('task::routed_swap::cancel', _cancelResponse);
  }

  /// Convenience for tests that only exercise routed swap and do not need a
  /// login. Prefer `KdfWalletFixture` + [applyTo] for anything end-to-end.
  KdfScript build() {
    final script = KdfScript();
    applyTo(script);
    return script;
  }

  // ---------------------------------------------------------------- responses

  Map<String, dynamic> _supportedCoinsResponse() {
    return {
      'mmrpc': '2.0',
      'result': {
        'provider': provider,
        'coins': [
          for (final entry in _supportedCoins.entries)
            {'coin': entry.key, 'chain_id': entry.value},
        ],
      },
    };
  }

  Map<String, dynamic> _quoteResponse(Map<String, dynamic> request) {
    final params = _params(request);
    final from = params['from'] as String? ?? '';
    final to = params['to'] as String? ?? '';
    final key = _pairKey(from, to);

    final error = _quoteErrors[key];
    if (error != null) {
      return _mmrpcError(error.errorType, error.errorData);
    }

    final quote = _quotes[key];
    if (quote == null) {
      throw StateError(
        'No routed_swap::quote scripted for "$from" -> "$to". Add one with '
        'fixture.quote(...), or script the failure with quoteFails(...). '
        'An unscripted pair is a scripting bug, not a NoRouteFound — the two '
        'render very differently and conflating them hides the difference.',
      );
    }

    return {
      'mmrpc': '2.0',
      'result': {
        'routes': [quote.toJson(provider)],
      },
    };
  }

  Map<String, dynamic> _initResponse(Map<String, dynamic> request) {
    final params = _params(request);
    if (_pendingRuns.isEmpty) {
      throw StateError(
        'task::routed_swap::init called with no run scripted. Enqueue one with '
        'fixture.run(RoutedSwapRun(...)).',
      );
    }
    final run = _pendingRuns.removeAt(0);
    final taskId = _nextTaskId++;
    final uuid = _formatUuid(_nextUuid++);

    final task = _RoutedTask(
      taskId: taskId,
      uuid: uuid,
      run: run,
      from: params['from'] as String? ?? run.from,
      to: params['to'] as String? ?? run.to,
      amount: params['amount'] as String? ?? run.amount,
      minToAmount: params['min_to_amount'] as String? ?? run.minToAmount,
      createdAt: _tick,
    );
    _tasks[taskId] = task;

    // §2: KDF allocates and persists the uuid *before* the task starts
    // executing, so a swap that dies between here and the first status read is
    // still recoverable. Writing the history row now rather than on first poll
    // is what makes that true.
    _writeHistory(task, status: 'InProgress');

    // §2: the response is `{task_id}` only, same as every other
    // `task::*::init`. The uuid surfaces via status or history.
    return {
      'mmrpc': '2.0',
      'result': {'task_id': taskId},
    };
  }

  Map<String, dynamic> _statusResponse(Map<String, dynamic> request) {
    final params = _params(request);
    final taskId = params['task_id'] as int?;
    final task = taskId == null ? null : _tasks[taskId];
    if (task == null) {
      // §3: a forgotten, cancelled or restarted task_id is a *top-level*
      // NoSuchTask, not a task Error result. The GUI cannot tell those four
      // cases apart from here — that is what history is for.
      return _mmrpcError('NoSuchTask', {'task_id': taskId});
    }

    // §3: defaults to true when omitted. Getting this wrong is silent and
    // destructive — a background poller that omits it deletes the terminal
    // result the foreground screen is about to read.
    final forgetIfFinished = params['forget_if_finished'] as bool? ?? true;

    final details = task.advance(provider);
    final status = task.currentStatus;

    if (status != 'InProgress') {
      _writeHistory(
        task,
        status: status,
        errorType: task.run.error?.errorType,
        finished: true,
      );
      if (forgetIfFinished) _tasks.remove(task.taskId);
    } else {
      _writeHistory(task, status: 'InProgress');
    }

    return {
      'mmrpc': '2.0',
      'result': {'status': status, 'details': details},
    };
  }

  Map<String, dynamic> _cancelResponse(Map<String, dynamic> request) {
    final params = _params(request);
    final taskId = params['task_id'] as int?;
    final task = taskId == null ? null : _tasks[taskId];
    if (task == null) return _mmrpcError('NoSuchTask', {'task_id': taskId});

    if (task.hasBroadcast) {
      // §4: the boundary is the Signing -> Broadcasting transition, not later
      // confirmation. Past it the handoff is irreversible and tracking
      // continues.
      return _mmrpcError('TaskCancellationNotAllowed', {
        'task_id': taskId,
        'current_state': task.currentState.wire,
      });
    }

    // §4: generic rpc_task cancellation removes the entry, so a concurrent or
    // later status lookup is NoSuchTask. The GUI must not wait for a pollable
    // `TaskCancelled` — it confirms through history.
    _writeHistory(
      task,
      status: 'Error',
      errorType: 'TaskCancelled',
      finished: true,
    );
    _tasks.remove(taskId);
    return {
      'mmrpc': '2.0',
      'result': {'result': 'success'},
    };
  }

  Map<String, dynamic> _historyResponse(Map<String, dynamic> request) {
    final params = _params(request);
    final limit = params['limit'] as int? ?? 20;
    final pageNumber = params['page_number'] as int? ?? 1;
    final uuidFilter = params['uuid'] as String?;
    final statusFilter = params['status_filter'] as String? ?? 'all';

    // Newest first on created_at, uuid as tiebreak. created_at is immutable, so
    // paging stays stable while an in-flight entry mutates underneath it.
    final entries =
        _history.where((entry) {
          if (uuidFilter != null && entry['uuid'] != uuidFilter) return false;
          switch (statusFilter) {
            case 'in_flight':
              return entry['status'] == 'InProgress';
            case 'terminal':
              return entry['status'] != 'InProgress';
            default:
              return true;
          }
        }).toList()..sort((a, b) {
          final byCreated = (b['created_at'] as int).compareTo(
            a['created_at'] as int,
          );
          return byCreated != 0
              ? byCreated
              : (a['uuid'] as String).compareTo(b['uuid'] as String);
        });

    final start = (pageNumber - 1) * limit;
    final page = start >= entries.length
        ? const <Map<String, dynamic>>[]
        : entries.skip(start).take(limit).toList();

    return {
      'mmrpc': '2.0',
      'result': {
        'entries': page,
        'total': entries.length,
        'limit': limit,
        'page_number': pageNumber,
      },
    };
  }

  // ------------------------------------------------------------------ helpers

  /// Every entry the fixture has persisted, newest first. Lets a test assert on
  /// durable state without going through the RPC.
  List<Map<String, dynamic>> get historyEntries =>
      List.unmodifiable(_history.reversed);

  void _writeHistory(
    _RoutedTask task, {
    required String status,
    String? errorType,
    bool finished = false,
  }) {
    final now = _tick;
    final existing = _history.indexWhere((e) => e['uuid'] == task.uuid);
    final entry = <String, dynamic>{
      'uuid': task.uuid,
      'provider': provider,
      'status': status,
      'state': task.currentState.wire,
      'kind': task.run.kind,
      'from': {'coin': task.from, 'amount': task.amount},
      'to': {'coin': task.to},
      'min_to_amount': task.minToAmount,
      'outcome': finished && status == 'Ok' ? task.run.outcome?.wire : null,
      'received': finished && status == 'Ok' ? task.run.receivedJson : null,
      'approve_tx_hash': task.approveTxHash,
      'source_tx_hash': task.sourceTxHash,
      'dest_tx_hash': finished && status == 'Ok' ? task.run.destTxHash : null,
      'error_type': errorType,
      'error_data': errorType == null ? null : task.run.error?.errorData,
      'sent': {'coin': task.from, 'amount': task.amount},
      'gas_spent': task.gasSpent,
      'approval_tx_hashes': [
        if (task.approveTxHash != null) task.approveTxHash,
      ],
      'created_at': task.createdAt,
      'updated_at': now,
      'finished_at': finished ? now : null,
    };

    if (existing >= 0) {
      _history[existing] = entry;
    } else {
      _history.add(entry);
    }
  }

  int get _tick => _clock++;

  String _pairKey(String from, String to) => '$from->$to';

  static String _formatUuid(int n) {
    final hex = n.toRadixString(16).padLeft(8, '0');
    return '$hex-0000-4000-8000-000000000000';
  }

  static Map<String, dynamic> _params(Map<String, dynamic> request) =>
      (request['params'] as Map<String, dynamic>?) ?? const {};

  /// A top-level MMRPC error — the shape `init` returns for a malformed request
  /// and `status`/`cancel` return for an unknown task. Distinct from a terminal
  /// task `Error` result, and §2 is explicit that the two are not
  /// interchangeable.
  static Map<String, dynamic> _mmrpcError(
    String errorType, [
    Map<String, dynamic>? errorData,
  ]) {
    return {
      'mmrpc': '2.0',
      'error': errorType,
      'error_path': 'routed_swap',
      'error_trace': 'harness',
      'error_type': errorType,
      if (errorData != null) 'error_data': errorData,
    };
  }
}

/// The §3 in-progress ladder.
///
/// Ordered. [broadcasting] is the cancellation boundary: everything before it
/// can still be cancelled with nothing sent, everything from it on is
/// committed to the network transport.
enum RoutedSwapState {
  /// KDF is re-quoting internally. Nothing is committed.
  fetchingQuote('FetchingQuote'),

  /// Reading the confirmed on-chain allowance. Brief.
  checkingAllowance('CheckingAllowance'),

  /// Sending an exact-amount ERC-20 approval. Skipped for native coins, and
  /// when a confirmed allowance already covers the sell amount.
  approving('Approving'),

  /// Signing locally. Cancellation is still effective here.
  signing('Signing'),

  /// The irreversible handoff has begun; cancellation is refused from here.
  broadcasting('Broadcasting'),

  /// Waiting for the source-chain transaction to confirm.
  waitingSourceConfirmation('WaitingSourceConfirmation'),

  /// Cross-chain only: following the bridge to the destination.
  trackingBridge('TrackingBridge');

  const RoutedSwapState(this.wire);

  /// The literal `state` string KDF puts on the wire.
  final String wire;

  /// Whether reaching this state means KDF has handed the transaction to the
  /// network. Cancellation is refused from here on.
  bool get isPostBroadcast => index >= RoutedSwapState.broadcasting.index;
}

/// The §3 terminal `Ok` outcomes.
///
/// Only [completed] is a success rendering. [partial] and [refunded] must be
/// surfaced prominently — a UI that shows either as a completed swap is lying
/// about where the user's money went.
enum RoutedSwapOutcome {
  /// The swap delivered the requested coin. The only success rendering.
  completed('completed'),

  /// Less than expected, or an intermediate token. `received` holds what the
  /// user actually got.
  partial('partial'),

  /// The swap did **not** happen; funds came back on the source chain.
  refunded('refunded');

  const RoutedSwapOutcome(this.wire);

  /// The literal `outcome` string KDF puts on the wire.
  final String wire;
}

/// A scripted `routed_swap::quote` route.
class RoutedSwapQuote {
  /// Creates a scripted route. [toAmountMin] must not exceed [toAmount] — the
  /// GUI asserts that relationship, so a fixture that inverts it tests nothing.
  const RoutedSwapQuote({
    required this.from,
    required this.to,
    required this.amount,
    required this.toAmount,
    required this.toAmountMin,
    this.kind = 'cross_chain',
    this.toolKey = 'stargateV2',
    this.toolName = 'Stargate V2',
    this.steps = const [],
    this.feeCosts = const [],
    this.gasCosts = const [],
    this.executionDurationS = 95,
  });

  /// KDF ticker being sold.
  final String from;

  /// KDF ticker being bought.
  final String to;

  /// Sell amount, in coin units as a decimal string — never wei.
  final String amount;

  /// Expected receive.
  final String toAmount;

  /// The guaranteed floor after slippage. §1 instructs the GUI to display this
  /// one, and to pass it to `init` as the guard.
  final String toAmountMin;

  /// `same_chain` or `cross_chain`. Same-chain completes in one tx, with no
  /// bridge phase and durations in seconds.
  final String kind;

  /// Provider key for the executing tool, e.g. `stargateV2`.
  final String toolKey;

  /// Human-readable tool name shown in the UI.
  final String toolName;

  /// Per-step breakdown, as emitted under `steps`.
  final List<Map<String, dynamic>> steps;

  /// Provider/protocol fees. An entry with `included: true` is already
  /// deducted from [toAmount] — the UI must not subtract it twice.
  final List<Map<String, dynamic>> feeCosts;

  /// Gas for the routed execution only. Approval gas is **extra** and is not
  /// represented here, which is the gap the GUI review asks to close.
  final List<Map<String, dynamic>> gasCosts;

  /// Provider's duration estimate for the whole route, in seconds.
  final int executionDurationS;

  /// Serialises to the `routes[0]` wire shape, echoing [provider].
  Map<String, dynamic> toJson(String provider) => {
    'provider': provider,
    'from': {'coin': from, 'amount': amount},
    'to': {'coin': to, 'amount': toAmount, 'amount_min': toAmountMin},
    'tool': {'key': toolKey, 'name': toolName},
    'kind': kind,
    'steps': steps,
    'fee_costs': feeCosts,
    'gas_costs': gasCosts,
    'execution_duration_s': executionDurationS,
  };
}

/// A scripted `routed_swap::quote` failure.
///
/// Named constructors cover the seven §1 error types with their documented
/// `error_data`, so a test cannot invent a payload the contract does not
/// describe.
class RoutedSwapQuoteError {
  const RoutedSwapQuoteError._(this.errorType, this.errorData);

  /// One of the coins is not activated in KDF.
  factory RoutedSwapQuoteError.coinNotActive(String coin) =>
      RoutedSwapQuoteError._('CoinNotActive', {'coin': coin});

  /// The pair is not eligible to quote for this provider (or is non-EVM in
  /// Phase 1).
  factory RoutedSwapQuoteError.pairNotSupported(
    String from,
    String to,
    String reason,
  ) => RoutedSwapQuoteError._('PairNotSupported', {
    'from': from,
    'to': to,
    'reason': reason,
  });

  /// No route exists right now. [reasons] carries the provider's per-tool
  /// breakdown when it reports one.
  factory RoutedSwapQuoteError.noRouteFound({
    List<String>? reasons,
    String? providerRequestId,
  }) => RoutedSwapQuoteError._('NoRouteFound', {
    if (reasons != null) 'reasons': reasons,
    if (providerRequestId != null) 'provider_request_id': providerRequestId,
  });

  /// The amount falls outside the route's accepted bounds.
  factory RoutedSwapQuoteError.amountOutOfBounds({
    required String param,
    required String value,
    String? min,
    String? max,
  }) => RoutedSwapQuoteError._('AmountOutOfBounds', {
    'param': param,
    'value': value,
    if (min != null) 'min': min,
    if (max != null) 'max': max,
  });

  /// Provider quota exhausted. The GUI should slow re-quoting and retry
  /// after a pause.
  factory RoutedSwapQuoteError.rateLimited({String? providerRequestId}) =>
      RoutedSwapQuoteError._('RateLimited', {
        if (providerRequestId != null) 'provider_request_id': providerRequestId,
      });

  /// Upstream provider error, with a human-readable message.
  factory RoutedSwapQuoteError.providerApiError(
    String message, {
    String? providerRequestId,
  }) => RoutedSwapQuoteError._('ProviderApiError', {
    'message': message,
    if (providerRequestId != null) 'provider_request_id': providerRequestId,
  });

  /// KDF could not reach the provider.
  factory RoutedSwapQuoteError.transportError(String message) =>
      RoutedSwapQuoteError._('TransportError', {'message': message});

  /// The `error_type` discriminator.
  final String errorType;

  /// The variant-specific `error_data` payload.
  final Map<String, dynamic> errorData;
}

/// A scripted terminal task error (§3's terminal-error table).
class RoutedSwapTaskError {
  const RoutedSwapTaskError._(this.errorType, this.errorData);

  /// The fresh quote came in below the accepted guard. Nothing was sent. The
  /// GUI shows the "price changed" dialog and retries `init` with the new
  /// `min_to_amount`.
  factory RoutedSwapTaskError.quoteWorsened({
    required RoutedSwapQuote freshRoute,
    String provider = 'lifi',
  }) => RoutedSwapTaskError._('QuoteWorsened', {
    'fresh_route': freshRoute.toJson(provider),
  });

  /// Not enough balance on the source chain, including routed execution gas
  /// and any approval gas shortfall.
  factory RoutedSwapTaskError.insufficientBalance({
    required String coin,
    required String available,
    required String required_,
  }) => RoutedSwapTaskError._('InsufficientBalance', {
    'coin': coin,
    'available': available,
    'required': required_,
  });

  /// The approval failed or reverted, or the confirmed allowance was still
  /// insufficient on recheck. Nothing was swapped.
  factory RoutedSwapTaskError.approvalFailed(String reason) =>
      RoutedSwapTaskError._('ApprovalFailed', {'reason': reason});

  /// The source transaction reverted; funds never left, minus gas.
  factory RoutedSwapTaskError.swapTxFailed({
    required String txHash,
    required String reason,
  }) => RoutedSwapTaskError._('SwapTxFailed', {
    'tx_hash': txHash,
    'reason': reason,
  });

  /// The provider reported FAILED with no refund resolution. Direct the user
  /// to the explorer link or support.
  factory RoutedSwapTaskError.bridgeFailed({
    required String txHash,
    String substatus = 'UNKNOWN_ERROR',
    String substatusMessage = 'The bridge reported a failure.',
    String? providerExplorerUrl,
  }) => RoutedSwapTaskError._('BridgeFailed', {
    'tx_hash': txHash,
    'substatus': substatus,
    'substatus_message': substatusMessage,
    if (providerExplorerUrl != null)
      'provider_explorer_url': providerExplorerUrl,
  });

  /// Terminal only before `Broadcasting`, when nothing was sent.
  factory RoutedSwapTaskError.internalError(String message) =>
      RoutedSwapTaskError._('InternalError', {'message': message});

  /// Terminal only before `Broadcasting`. After broadcast, §3 is explicit that
  /// transport problems keep the task in `TrackingBridge` and KDF retries — so
  /// a run that scripts this past the boundary is a contract violation and
  /// [RoutedSwapRun] rejects it.
  factory RoutedSwapTaskError.transportError(String message) =>
      RoutedSwapTaskError._('TransportError', {'message': message});

  /// The `error_type` discriminator.
  final String errorType;

  /// The variant-specific `error_data` payload.
  final Map<String, dynamic> errorData;

  /// Whether the contract permits this error only before `Broadcasting`.
  bool get mustBePreBroadcast =>
      errorType == 'TransportError' || errorType == 'InternalError';
}

/// One scripted routed-swap execution.
///
/// The [states] ladder is walked one entry per `status` poll. Skipping states
/// is legal and deliberate: the contract only promises the ladder's *order*,
/// and a GUI that assumes it observes every state breaks the first time a poll
/// lands between two transitions — which SSE being best-effort guarantees will
/// happen.
class RoutedSwapRun {
  /// Scripts one execution. Throws when the requested terminal state cannot
  /// occur at the point the [states] ladder reaches — see
  /// [RoutedSwapTaskError.mustBePreBroadcast].
  RoutedSwapRun({
    this.from = 'USDT-PLG20',
    this.to = 'USDC-ERC20',
    this.amount = '100.5',
    this.minToAmount = '99.71',
    this.kind = 'cross_chain',
    List<RoutedSwapState>? states,
    RoutedSwapOutcome? outcome,
    this.error,
    this.receivedCoin,
    this.receivedAmount = '100.02',
    this.receivedSymbol,
    this.approveTxHash,
    this.sourceTxHash = '0xsource',
    this.destTxHash = '0xdest',
    this.gasSpent = const [],
  }) : states = states ?? _defaultLadder(error),
       // A terminal read is either Ok or Error, never both. Leaving `outcome`
       // null on a successful run means `completed` — the common case — so the
       // caller only names an outcome when it is one of the two that must not
       // be rendered as success.
       outcome = error != null
           ? null
           : (outcome ?? RoutedSwapOutcome.completed) {
    if (error != null && outcome != null) {
      throw ArgumentError(
        'A run cannot both succeed and fail. Pass `error:` for a terminal '
        'Error, or `outcome:` for a terminal Ok — not both.',
      );
    }
    final err = error;
    if (err != null && err.mustBePreBroadcast) {
      final reachesBroadcast = this.states.any((s) => s.isPostBroadcast);
      if (reachesBroadcast) {
        throw ArgumentError(
          '${err.errorType} is terminal only before Broadcasting (§3). This '
          'run reaches '
          '${this.states.lastWhere((s) => s.isPostBroadcast).wire}, '
          'where the contract says KDF must keep tracking instead of failing. '
          'Scripting it here would let the GUI be tested against behaviour KDF '
          'has promised never to produce.',
        );
      }
    }
  }

  /// KDF ticker being sold.
  final String from;

  /// KDF ticker being bought.
  final String to;

  /// Sell amount in coin units.
  final String amount;

  /// The `amount_min` the user accepted, passed to `init` as the guard.
  final String minToAmount;

  /// `same_chain` or `cross_chain`.
  final String kind;

  /// The in-progress states this run reports, in order, one per poll.
  final List<RoutedSwapState> states;

  /// Terminal success outcome, or null when the run ends in [error].
  final RoutedSwapOutcome? outcome;

  /// Terminal error, or null when the run succeeds.
  final RoutedSwapTaskError? error;

  /// The coin actually received. Defaults to [to]; set it to something else to
  /// model `partial` delivering an intermediate token, or `refunded` returning
  /// the source coin.
  final String? receivedCoin;

  /// Amount actually received.
  final String receivedAmount;

  /// Set instead of [receivedCoin] when the received token does not map to a
  /// KDF ticker. §1 defines this fallback for `fee_costs`; §3 leaves `received`
  /// unspecified, so this is the GUI's proposed reading and a test that relies
  /// on it is testing an unratified assumption.
  final String? receivedSymbol;

  /// Approval transaction hash, when the run includes an approval step.
  final String? approveTxHash;

  /// Source-chain transaction hash.
  final String sourceTxHash;

  /// Destination-chain transaction hash. Omitted for a refund.
  final String destTxHash;

  /// Gas actually spent, for the provisional history `gas_spent` field.
  final List<Map<String, dynamic>> gasSpent;

  bool get _terminatesOk => error == null;

  /// The `received` payload for a terminal `Ok`, or null when the run fails.
  Map<String, dynamic>? get receivedJson {
    if (!_terminatesOk) return null;
    return {
      if (receivedSymbol == null) 'coin': receivedCoin ?? to,
      if (receivedSymbol != null) 'symbol': receivedSymbol,
      'amount': receivedAmount,
    };
  }

  /// A run that fails before broadcast never reaches the post-broadcast states;
  /// one that succeeds walks the whole ladder.
  static List<RoutedSwapState> _defaultLadder(RoutedSwapTaskError? error) {
    if (error != null && error.mustBePreBroadcast) {
      return const [
        RoutedSwapState.fetchingQuote,
        RoutedSwapState.checkingAllowance,
      ];
    }
    return RoutedSwapState.values;
  }
}

/// Mutable per-task state. One instance per `init`, resolved by `task_id` — the
/// same reason `KdfWalletFixture` allocates ids rather than using a per-method
/// cursor: `task::routed_swap::status` is one method serving every concurrent
/// swap.
class _RoutedTask {
  _RoutedTask({
    required this.taskId,
    required this.uuid,
    required this.run,
    required this.from,
    required this.to,
    required this.amount,
    required this.minToAmount,
    required this.createdAt,
  });

  final int taskId;
  final String uuid;
  final RoutedSwapRun run;
  final String from;
  final String to;
  final String amount;
  final String? minToAmount;

  /// Stamped at `init`, not at first poll. History is sorted on this, and a
  /// record written before the first status read would otherwise sort as if it
  /// were the oldest swap in the list.
  final int createdAt;

  int _cursor = -1;
  bool _terminal = false;

  RoutedSwapState get currentState =>
      run.states[_cursor.clamp(0, run.states.length - 1)];

  bool get hasBroadcast =>
      _cursor >= 0 &&
      run.states.take(_cursor + 1).any((s) => s.isPostBroadcast);

  String get currentStatus {
    if (!_terminal) return 'InProgress';
    return run.error == null ? 'Ok' : 'Error';
  }

  String? get approveTxHash =>
      _reached(RoutedSwapState.approving) ? run.approveTxHash : null;

  String? get sourceTxHash =>
      _reached(RoutedSwapState.waitingSourceConfirmation)
      ? run.sourceTxHash
      : null;

  List<Map<String, dynamic>> get gasSpent => run.gasSpent;

  bool _reached(RoutedSwapState state) =>
      _cursor >= 0 && run.states.take(_cursor + 1).contains(state);

  /// Advances one poll and returns the `details` payload for it.
  Map<String, dynamic> advance(String provider) {
    if (_terminal) {
      // A terminal read is repeatable while the task still exists — that is
      // what forget_if_finished: false buys the caller.
      return _terminalDetails(provider);
    }

    _cursor++;
    if (_cursor >= run.states.length) {
      _terminal = true;
      return _terminalDetails(provider);
    }
    return _inProgressDetails(provider);
  }

  /// §3: every InProgress payload carries `uuid`, `provider` and `state` at the
  /// top level of `details`, plus whatever that state adds.
  ///
  /// Only the three states the table gives extra fields to carry any; the rest
  /// are deliberately bare. A fixture that padded every state with a tx hash
  /// would let a GUI read a hash the contract never promises at that point.
  Map<String, dynamic> _inProgressDetails(String provider) {
    final state = currentState;
    final details = <String, dynamic>{
      'uuid': uuid,
      'provider': provider,
      'state': state.wire,
    };

    switch (state) {
      case RoutedSwapState.approving:
        details['approve_tx_hash'] = run.approveTxHash ?? '0xapprove';
      case RoutedSwapState.waitingSourceConfirmation:
        details['tx_hash'] = run.sourceTxHash;
      case RoutedSwapState.trackingBridge:
        details.addAll({
          'tx_hash': run.sourceTxHash,
          'substatus': 'WAIT_DESTINATION_TRANSACTION',
          'substatus_message': 'Waiting for the destination transaction.',
          'provider_explorer_url':
              'https://explorer.example/tx/${run.sourceTxHash}',
          'execution_duration_s': 95,
        });
      case RoutedSwapState.fetchingQuote:
      case RoutedSwapState.checkingAllowance:
      case RoutedSwapState.signing:
      case RoutedSwapState.broadcasting:
        break;
    }

    return details;
  }

  Map<String, dynamic> _terminalDetails(String provider) {
    final error = run.error;
    if (error == null) {
      return {
        'uuid': uuid,
        'provider': provider,
        'outcome': (run.outcome ?? RoutedSwapOutcome.completed).wire,
        'received': run.receivedJson,
        if (sourceTxHash != null) 'source_tx_hash': sourceTxHash,
        if (run.outcome != RoutedSwapOutcome.refunded)
          'dest_tx_hash': run.destTxHash,
        'provider_explorer_url':
            'https://explorer.example/tx/${run.sourceTxHash}',
      };
    }
    // §3: an Error keeps uuid and provider beside the standard serialized
    // MmError fields, with variant payloads in error_data.
    return {
      'uuid': uuid,
      'provider': provider,
      'error': error.errorType,
      'error_path': 'routed_swap',
      'error_trace': 'harness',
      'error_type': error.errorType,
      'error_data': {'uuid': uuid, ...error.errorData},
    };
  }
}
