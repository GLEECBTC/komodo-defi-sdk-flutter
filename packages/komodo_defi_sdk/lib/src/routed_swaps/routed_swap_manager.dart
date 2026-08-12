import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;
import 'package:komodo_defi_sdk/src/routed_swaps/routed_swap_types.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Resolves a KDF coin ticker to a wallet asset, or null when the wallet does
/// not know it.
typedef RoutedSwapAssetResolver = AssetId? Function(String ticker);

/// Emits whenever KDF reports movement on a task.
///
/// The payload is irrelevant — an event only means "check again sooner". The
/// stream is best-effort and may miss transitions entirely, so it is a latency
/// optimisation layered over polling, never a substitute for it.
typedef RoutedSwapTaskNudges = Stream<void> Function(int taskId);

/// A running or recoverable routed swap.
///
/// Deliberately exposes no task id. The task id is in-memory, dies on restart,
/// cancellation, or a terminal read, and is the wrong thing for callers to
/// hold. [uuid] is the durable handle and is resolved before this object is
/// handed out.
class RoutedSwapHandle {
  RoutedSwapHandle._({
    required this.uuid,
    required Stream<RoutedSwapProgress> progress,
    required Future<void> Function() cancel,
  }) : _progress = progress,
       _cancel = cancel;

  /// The durable swap id.
  final String uuid;

  final Stream<RoutedSwapProgress> _progress;
  final Future<void> Function() _cancel;

  /// Progress updates until the swap reaches a terminal state.
  ///
  /// Broadcast: several listeners may follow the same swap, and a screen that
  /// subscribes late still receives every update from that point on. Missed
  /// and duplicate observations are already reconciled internally.
  Stream<RoutedSwapProgress> get progress => _progress;

  /// Resolves with the terminal snapshot.
  Future<RoutedSwapProgress> get result async =>
      _progress.firstWhere((p) => p.isTerminal);

  /// Stops the swap, if it has not been broadcast.
  ///
  /// Throws [RoutedSwapNotCancellableException] once the transaction has been
  /// handed to the network. An approval already confirmed on-chain cannot be
  /// undone, so the user may still have spent gas.
  Future<void> cancel() => _cancel();
}

/// Routed (aggregator-executed) swaps.
///
/// KDF owns the lifecycle: it quotes, approves, signs, broadcasts and tracks
/// the bridge. This manager owns everything a caller would otherwise have to
/// get right by hand — allocating and recovering the durable id, preferring
/// the event stream but never trusting it, never destroying a terminal result,
/// and falling back to persistent history when the in-memory task is gone.
///
/// Nothing in the public surface mentions a task.
class RoutedSwapManager {
  /// Creates the manager. Wired by the SDK container.
  RoutedSwapManager({
    required ApiClient client,
    required RoutedSwapAssetResolver resolveAsset,
    RoutedSwapTaskNudges? taskNudges,
    Duration pollInterval = const Duration(seconds: 3),
    Duration streamStaleAfter = const Duration(seconds: 8),
  }) : _client = client,
       _resolveAsset = resolveAsset,
       _taskNudges = taskNudges,
       _pollInterval = pollInterval,
       _streamStaleAfter = streamStaleAfter;

  final ApiClient _client;
  final RoutedSwapAssetResolver _resolveAsset;
  final RoutedSwapTaskNudges? _taskNudges;

  final Map<String, _RoutedSwapSession> _sessions = {};

  /// How often to poll when the event stream is quiet.
  final Duration _pollInterval;

  /// How long to trust the event stream before polling anyway.
  ///
  /// KDF sends task events with a non-blocking try-send, so a busy or briefly
  /// disconnected client silently misses transitions. Polling is the source of
  /// truth; the stream only makes it feel immediate.
  final Duration _streamStaleAfter;

  /// Wallet assets that are eligible to be quoted.
  ///
  /// Eligible is not the same as routable: a pair listed here can still fail
  /// to price on coverage, liquidity or amount bounds. Always quote before
  /// telling a user a swap is possible.
  ///
  /// Assets the provider supports but the wallet has not activated are
  /// excluded, because both sides of a routed swap must be activated in KDF.
  Future<Set<AssetId>> eligibleAssets({String? provider}) async {
    final response = await _client.rpc.routedSwap.supportedCoins(
      provider: provider,
    );
    final eligible = <AssetId>{};
    for (final coin in response.coins) {
      final assetId = _resolveAssetId(coin.coin);
      if (assetId != null) eligible.add(assetId);
    }
    return eligible;
  }

  /// Prices a swap. Reserves nothing and moves nothing.
  ///
  /// Throws the typed quote errors — no route, rate limited, amount out of
  /// bounds, pair unsupported — as exceptions, because none of them produce a
  /// usable offer.
  Future<RoutedSwapOffer> quote({
    required AssetId from,
    required AssetId to,
    required Decimal amount,
    double? slippage,
    rpc.RoutedSwapOrder? order,
    String? provider,
  }) async {
    final response = await _client.rpc.routedSwap.quote(
      from: from.id,
      to: to.id,
      amount: amount.toString(),
      slippage: slippage,
      order: order,
      provider: provider,
    );

    final route = response.best;
    if (route == null) {
      throw StateError(
        'The provider returned no route for ${from.id} -> ${to.id}. This is a '
        'protocol violation: a successful quote must contain one route, and a '
        'failure must be a typed error.',
      );
    }
    return _offerFrom(route, from: from, to: to, slippage: slippage);
  }

  /// Starts a swap and returns a handle whose [RoutedSwapHandle.uuid] is
  /// already resolved.
  ///
  /// The durable id is read back before this returns, so a caller that
  /// persists it can always recover the swap — including when the process is
  /// killed moments later, which on mobile is routine rather than exotic.
  ///
  /// The guard sent to KDF is the offer's guaranteed receive, so a swap can
  /// never be started against a number the user was not shown.
  Future<RoutedSwapHandle> start(RoutedSwapOffer offer) async {
    final init = await _client.rpc.routedSwap.init(
      from: offer.from.id,
      to: offer.to.id,
      amount: offer.sellAmount.toString(),
      minToAmount: offer.guaranteedReceive.toString(),
      slippage: offer.slippage,
      provider: offer.provider,
    );

    // Resolve the uuid before handing back a handle. Everything after this
    // point is recoverable; the window before it is not, so it is closed here
    // rather than left to each caller.
    final first = await _client.rpc.routedSwap.status(init.taskId);
    final session = _RoutedSwapSession(
      uuid: first.details.uuid,
      taskId: init.taskId,
      manager: this,
      offer: offer,
      seed: _progressFrom(first.details, offer: offer),
    );
    _sessions[session.uuid] = session;

    return RoutedSwapHandle._(
      uuid: session.uuid,
      progress: session.stream,
      cancel: session.cancel,
    );
  }

  /// Re-attaches to a swap by its durable id.
  ///
  /// Returns the live session when one is running in this process, and
  /// otherwise a handle that replays the persisted record — so a screen opened
  /// after a restart behaves the same as one that never closed.
  ///
  /// Throws [RoutedSwapNotFoundException] when nothing is known about [uuid].
  Future<RoutedSwapHandle> watch(String uuid) async {
    final live = _sessions[uuid];
    if (live != null && !live.isClosed) {
      return RoutedSwapHandle._(
        uuid: uuid,
        progress: live.stream,
        cancel: live.cancel,
      );
    }

    final record = await _recordFor(uuid);
    if (record == null) throw RoutedSwapNotFoundException(uuid);

    // A swap KDF is still tracking after a restart has no task id any client
    // can hold, so history polling is the only way to follow it.
    final replay = record.isInFlight
        ? _historyPollingStream(uuid)
        : Stream<RoutedSwapProgress>.value(_progressFromRecord(record));

    return RoutedSwapHandle._(
      uuid: uuid,
      progress: replay,
      cancel: () async => throw RoutedSwapNotCancellableException(
        uuid,
        _progressFromRecord(record).phase,
      ),
    );
  }

  /// Swaps that have not finished, newest first.
  ///
  /// The cold-start question: after a relaunch, what is still running? A
  /// 30-minute bridge outlives most app sessions, so this is the normal path.
  Future<List<RoutedSwapProgress>> inFlight({int limit = 20}) async {
    final page = await _client.rpc.routedSwap.history(
      limit: limit,
      filter: rpc.RoutedSwapHistoryFilter.inFlight,
    );
    return page.entries.map(_progressFromRecord).toList();
  }

  /// Past and present swaps, newest first.
  Future<List<RoutedSwapProgress>> history({
    int limit = 20,
    int pageNumber = 1,
  }) async {
    final page = await _client.rpc.routedSwap.history(
      limit: limit,
      pageNumber: pageNumber,
    );
    return page.entries.map(_progressFromRecord).toList();
  }

  /// Releases every live session.
  Future<void> dispose() async {
    final sessions = _sessions.values.toList();
    _sessions.clear();
    for (final session in sessions) {
      await session.close();
    }
  }

  // ------------------------------------------------------------- internals

  AssetId? _resolveAssetId(String ticker) => _resolveAsset(ticker);

  Future<rpc.RoutedSwapHistoryEntry?> _recordFor(String uuid) async {
    final page = await _client.rpc.routedSwap.history(limit: 1, uuid: uuid);
    return page.entries.isEmpty ? null : page.entries.first;
  }

  /// Polls history for a swap KDF is tracking but no client can address.
  Stream<RoutedSwapProgress> _historyPollingStream(String uuid) async* {
    while (true) {
      final record = await _recordFor(uuid);
      if (record == null) throw RoutedSwapNotFoundException(uuid);
      final progress = _progressFromRecord(record);
      yield progress;
      if (progress.isTerminal) return;
      await Future<void>.delayed(_pollInterval);
    }
  }

  RoutedSwapOffer _offerFrom(
    rpc.RoutedSwapRoute route, {
    required AssetId from,
    required AssetId to,
    double? slippage,
  }) {
    final costs = <RoutedSwapCost>[
      for (final fee in route.feeCosts)
        RoutedSwapCost(
          label: fee.name,
          amount: Decimal.parse(fee.amount.amount),
          kind: RoutedSwapCostKind.providerFee,
          isDeductedFromReceive: fee.included,
          assetId: fee.amount.coin == null
              ? null
              : _resolveAssetId(fee.amount.coin!),
          symbol: fee.amount.symbol,
          usdValue: fee.amountUsd == null
              ? null
              : Decimal.parse(fee.amountUsd!),
        ),
      for (final gas in route.gasCosts)
        RoutedSwapCost(
          label: 'Network fee',
          amount: Decimal.parse(gas.amount.amount),
          kind: RoutedSwapCostKind.gas,
          isDeductedFromReceive: false,
          assetId: gas.amount.coin == null
              ? null
              : _resolveAssetId(gas.amount.coin!),
          symbol: gas.amount.symbol,
          usdValue: gas.amountUsd == null
              ? null
              : Decimal.parse(gas.amountUsd!),
        ),
    ];

    return RoutedSwapOffer(
      from: from,
      to: to,
      sellAmount: Decimal.parse(route.from.amount),
      expectedReceive: Decimal.parse(route.to.amount),
      guaranteedReceive: Decimal.parse(route.toMinimum.amount),
      toolName: route.tool.name,
      toolLogoUrl: route.tool.logoUrl,
      isCrossChain: route.kind == rpc.RoutedSwapRouteKind.crossChain,
      costs: costs,
      estimatedDuration: route.executionDurationS == null
          ? null
          : Duration(seconds: route.executionDurationS!),
      quotedAt: DateTime.now(),
      // The quote never says whether an approval is coming. A native sell
      // never needs one; a token sell may need one or two. Deriving it from
      // the asset is the only honest answer available, and it is better than
      // making every caller re-learn the rule.
      mayRequireApproval: !_isNativeAsset(from),
      provider: route.provider,
      slippage: slippage,
    );
  }

  bool _isNativeAsset(AssetId assetId) => assetId.parentId == null;

  RoutedSwapProgress _progressFrom(
    rpc.RoutedSwapStatus status, {
    RoutedSwapOffer? offer,
  }) {
    switch (status) {
      case rpc.RoutedSwapInProgress():
        return RoutedSwapProgress(
          uuid: status.uuid,
          phase: _phaseOf(status.state),
          canCancel: status.state.isCancellable,
          rawState: status.rawState,
          approvalTxHash: status.approveTxHash,
          sourceTxHash: status.txHash,
          explorerUrl: status.providerExplorerUrl,
          providerStatusDetail: status.substatusMessage ?? status.substatus,
          estimatedDuration: status.executionDurationS == null
              ? null
              : Duration(seconds: status.executionDurationS!),
        );
      case rpc.RoutedSwapSuccess():
        return RoutedSwapProgress(
          uuid: status.uuid,
          phase: RoutedSwapPhase.finished,
          canCancel: false,
          receipt: RoutedSwapReceipt(
            outcome: status.outcome,
            amount: Decimal.parse(status.received.amount),
            assetId: status.received.coin == null
                ? null
                : _resolveAssetId(status.received.coin!),
            symbol: status.received.symbol,
          ),
          sourceTxHash: status.sourceTxHash,
          destinationTxHash: status.destTxHash,
          explorerUrl: status.providerExplorerUrl,
        );
      case rpc.RoutedSwapFailure():
        return RoutedSwapProgress(
          uuid: status.uuid,
          phase: RoutedSwapPhase.failed,
          canCancel: false,
          failure: _failureFrom(
            errorType: status.errorType,
            message: status.message,
            data: status.errorData,
            fundsUntouched: status.nothingWasSent,
            offer: offer,
          ),
        );
    }
  }

  RoutedSwapProgress _progressFromRecord(rpc.RoutedSwapHistoryEntry record) {
    if (record.errorType != null) {
      return RoutedSwapProgress(
        uuid: record.uuid,
        phase: RoutedSwapPhase.failed,
        canCancel: false,
        approvalTxHash: record.approveTxHash,
        sourceTxHash: record.sourceTxHash,
        failure: _failureFrom(
          errorType: record.errorType!,
          message: record.errorType!,
          data: record.errorData ?? const {},
          // A record only reaches history's terminal error states after KDF
          // has stopped, so trust the same conservative rule used live.
          fundsUntouched: const {
            'TaskCancelled',
            'AbortedOnRestart',
            'QuoteWorsened',
            'InsufficientBalance',
            'ApprovalFailed',
          }.contains(record.errorType),
        ),
      );
    }

    if (record.status == 'Ok' && record.received != null) {
      return RoutedSwapProgress(
        uuid: record.uuid,
        phase: RoutedSwapPhase.finished,
        canCancel: false,
        receipt: RoutedSwapReceipt(
          outcome: record.outcome ?? rpc.RoutedSwapOutcome.unknown,
          amount: Decimal.parse(record.received!.amount),
          assetId: record.received!.coin == null
              ? null
              : _resolveAssetId(record.received!.coin!),
          symbol: record.received!.symbol,
        ),
        sourceTxHash: record.sourceTxHash,
        destinationTxHash: record.destTxHash,
      );
    }

    final state = record.state == null
        ? rpc.RoutedSwapState.unknown
        : rpc.RoutedSwapState.parse(record.state!);
    return RoutedSwapProgress(
      uuid: record.uuid,
      phase: _phaseOf(state),
      // A record recovered from history has no addressable task, so there is
      // nothing to cancel even when the phase would otherwise allow it.
      canCancel: false,
      rawState: record.state,
      approvalTxHash: record.approveTxHash,
      sourceTxHash: record.sourceTxHash,
    );
  }

  RoutedSwapFailure _failureFrom({
    required String errorType,
    required String message,
    required Map<String, dynamic> data,
    required bool fundsUntouched,
    RoutedSwapOffer? offer,
  }) {
    final kind = switch (errorType) {
      'QuoteWorsened' => RoutedSwapFailureKind.priceMoved,
      'InsufficientBalance' => RoutedSwapFailureKind.insufficientBalance,
      'ApprovalFailed' => RoutedSwapFailureKind.approvalFailed,
      'SwapTxFailed' => RoutedSwapFailureKind.swapTransactionFailed,
      'BridgeFailed' => RoutedSwapFailureKind.bridgeFailed,
      'AbortedOnRestart' => RoutedSwapFailureKind.abortedOnRestart,
      'TaskCancelled' => RoutedSwapFailureKind.cancelled,
      _ => RoutedSwapFailureKind.unknown,
    };

    RoutedSwapOffer? freshOffer;
    if (kind == RoutedSwapFailureKind.priceMoved && offer != null) {
      final raw = data['fresh_route'];
      if (raw is Map<String, dynamic>) {
        freshOffer = _offerFrom(
          rpc.RoutedSwapRoute.fromJson(raw),
          from: offer.from,
          to: offer.to,
          slippage: offer.slippage,
        );
      }
    }

    return RoutedSwapFailure(
      kind: kind,
      message: message,
      fundsUntouched: fundsUntouched,
      details: data,
      freshOffer: freshOffer,
    );
  }

  static RoutedSwapPhase _phaseOf(rpc.RoutedSwapState state) => switch (state) {
    rpc.RoutedSwapState.fetchingQuote ||
    rpc.RoutedSwapState.checkingAllowance => RoutedSwapPhase.preparing,
    rpc.RoutedSwapState.approving => RoutedSwapPhase.approving,
    rpc.RoutedSwapState.signing => RoutedSwapPhase.signing,
    rpc.RoutedSwapState.broadcasting => RoutedSwapPhase.sending,
    rpc.RoutedSwapState.waitingSourceConfirmation => RoutedSwapPhase.confirming,
    rpc.RoutedSwapState.trackingBridge => RoutedSwapPhase.bridging,
    rpc.RoutedSwapState.unknown => RoutedSwapPhase.unknown,
  };
}

/// Drives one live swap: event stream where available, polling as the truth,
/// history once the task is gone.
class _RoutedSwapSession {
  _RoutedSwapSession({
    required this.uuid,
    required this.taskId,
    required RoutedSwapManager manager,
    required RoutedSwapOffer offer,
    required RoutedSwapProgress seed,
  }) : _manager = manager,
       _offer = offer,
       _latest = seed {
    _controller = StreamController<RoutedSwapProgress>.broadcast(
      onListen: _start,
      onCancel: () {
        if (!_controller.hasListener) _stopWatching();
      },
    );
  }

  final String uuid;
  final int taskId;
  final RoutedSwapManager _manager;
  final RoutedSwapOffer _offer;

  late final StreamController<RoutedSwapProgress> _controller;
  StreamSubscription<void>? _events;
  Timer? _timer;
  DateTime? _lastEventAt;
  RoutedSwapProgress _latest;
  var _started = false;
  var _finished = false;
  var _polling = false;

  bool get isClosed => _controller.isClosed;

  /// The progress stream, seeded with the snapshot taken at start so a late
  /// subscriber is never left with a blank screen waiting for the next poll.
  Stream<RoutedSwapProgress> get stream async* {
    yield _latest;
    yield* _controller.stream;
  }

  void _start() {
    if (_started) return;
    _started = true;

    // Best-effort. KDF drops events on a slow client, so this only makes
    // updates feel immediate — the timer below is what guarantees progress.
    try {
      _events = _manager._taskNudges?.call(taskId).listen((_) {
        _lastEventAt = DateTime.now();
        unawaited(_refresh());
      }, onError: (_) {});
    } on Object {
      // A stream that will not start is not a failure worth surfacing; the
      // poller covers it.
    }

    _timer = Timer.periodic(_manager._pollInterval, (_) {
      final last = _lastEventAt;
      final streamIsFresh =
          last != null &&
          DateTime.now().difference(last) < _manager._streamStaleAfter;
      if (!streamIsFresh) unawaited(_refresh());
    });

    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_finished || _polling || _controller.isClosed) return;
    _polling = true;
    try {
      // Never forget: a terminal result read once and discarded cannot be
      // recovered from the task, and any other listener would lose it.
      // Never forget the result: reading a terminal status with
      // forget_if_finished would destroy it for every other listener.
      final status = await _manager._client.rpc.routedSwap.status(taskId);
      _emit(_manager._progressFrom(status.details, offer: _offer));
    } on Object catch (_) {
      // The task is gone — forgotten, cancelled, or lost to a restart. The
      // swap itself may be entirely fine, so resolve it from the durable
      // record rather than reporting a failure the user did not have.
      await _resolveFromHistory();
    } finally {
      _polling = false;
    }
  }

  Future<void> _resolveFromHistory() async {
    try {
      final record = await _manager._recordFor(uuid);
      if (record == null) return;
      _emit(_manager._progressFromRecord(record));
    } on Object catch (error, trace) {
      if (!_controller.isClosed) _controller.addError(error, trace);
    }
  }

  void _emit(RoutedSwapProgress progress) {
    if (_controller.isClosed) return;
    _latest = progress;
    _controller.add(progress);
    if (progress.isTerminal) {
      _finished = true;
      _stopWatching();
    }
  }

  Future<void> cancel() async {
    if (!_latest.canCancel) {
      throw RoutedSwapNotCancellableException(uuid, _latest.phase);
    }
    try {
      await _manager._client.rpc.routedSwap.cancel(taskId);
    } on Object {
      // Losing the race is the expected failure here: the transaction was
      // broadcast between the check and the call.
      throw RoutedSwapNotCancellableException(uuid, _latest.phase);
    }
    // Cancellation removes the task, so the outcome is only readable in the
    // durable record.
    await _resolveFromHistory();
  }

  void _stopWatching() {
    _timer?.cancel();
    _timer = null;
    unawaited(_events?.cancel());
    _events = null;
  }

  Future<void> close() async {
    _stopWatching();
    await _controller.close();
  }
}
