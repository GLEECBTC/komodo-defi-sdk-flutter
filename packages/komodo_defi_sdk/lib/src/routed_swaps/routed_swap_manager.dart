import 'dart:async';
import 'dart:math' as math;

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
abstract interface class RoutedSwapHandle {
  /// The durable swap id.
  String get uuid;

  /// The most recent snapshot.
  RoutedSwapProgress get latest;

  /// Progress until the swap reaches a terminal state, then done.
  ///
  /// Every access returns a fresh stream that first replays [latest], so any
  /// number of listeners may follow the same swap and a late subscriber is
  /// never left blank. Missed and duplicate observations are reconciled
  /// internally; an unchanged snapshot is not re-emitted.
  Stream<RoutedSwapProgress> get progress;

  /// Resolves with the terminal snapshot.
  Future<RoutedSwapProgress> get result;

  /// Stops the swap, if it has not been broadcast.
  ///
  /// Throws [RoutedSwapNotCancellableException] once the transaction has been
  /// handed to the network, when the swap has already ended, or when it is
  /// only known from the durable record. Throws
  /// [RoutedSwapCancelUnconfirmedException] when the answer could not be
  /// read. An approval already confirmed on-chain cannot be undone.
  Future<void> cancel();
}

/// Routed (aggregator-executed) swaps.
///
/// KDF owns the lifecycle: it quotes, approves, signs, broadcasts and tracks
/// the bridge. This manager owns everything a caller would otherwise have to
/// get right by hand — resolving and recovering the durable id, preferring the
/// event stream but never trusting it, reading a terminal result before
/// releasing it, and falling back to persistent history when the in-memory
/// task is gone.
///
/// Nothing in the public surface mentions a task.
class RoutedSwapManager {
  /// Creates the manager. Wired by the SDK container.
  RoutedSwapManager({
    required ApiClient client,
    required RoutedSwapAssetResolver resolveAsset,
    RoutedSwapTaskNudges? taskNudges,
    Duration pollInterval = const Duration(seconds: 3),
    Duration historyPollInterval = const Duration(seconds: 5),
    Duration maxBackoff = const Duration(seconds: 30),
    int delayedAfterFailures = 3,
    Duration firstReadRetryDelay = const Duration(milliseconds: 500),
    int firstReadAttempts = 3,
  }) : _client = client,
       _resolveAsset = resolveAsset,
       _taskNudges = taskNudges,
       _pollInterval = pollInterval,
       _historyPollInterval = historyPollInterval,
       _maxBackoff = maxBackoff,
       _delayedAfterFailures = delayedAfterFailures,
       _firstReadRetryDelay = firstReadRetryDelay,
       _firstReadAttempts = firstReadAttempts;

  final ApiClient _client;
  final RoutedSwapAssetResolver _resolveAsset;
  final RoutedSwapTaskNudges? _taskNudges;
  final Duration _pollInterval;
  final Duration _historyPollInterval;
  final Duration _maxBackoff;
  final int _delayedAfterFailures;
  final Duration _firstReadRetryDelay;
  final int _firstReadAttempts;

  final Map<String, _RoutedSwapSession> _sessions = {};

  /// How much of the probed network fee a native-coin Max holds back.
  ///
  /// Gas moves between the probe and the swap, so the reserve carries a
  /// margin; leftover dust is the cheaper failure than a swap that cannot pay
  /// for itself.
  static final Decimal maxSellFeeMargin = Decimal.parse('1.25');

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
      final assetId = _resolveAsset(coin.coin);
      if (assetId != null) eligible.add(assetId);
    }
    return eligible;
  }

  /// Prices a swap. Reserves nothing and moves nothing.
  ///
  /// Throws a typed [rpc.RoutedSwapRpcException] — no route, rate limited,
  /// amount out of bounds, pair unsupported, … — because none of them produce
  /// a usable offer.
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
    return _offerFrom(
      route,
      from: from,
      to: to,
      order: order,
      slippage: slippage,
    );
  }

  /// The largest amount of [from] that can be sold for [to] while keeping the
  /// source chain's gas.
  ///
  /// Interim, until the contract grows a max option of its own: a token sell
  /// may use its whole [balance], because its gas is paid in the chain's
  /// native coin; a native sell holds back the route's network fee, probed at
  /// the full balance, times [maxSellFeeMargin].
  Future<RoutedSwapMaxSell> maxSellAmount({
    required AssetId from,
    required AssetId to,
    required Decimal balance,
    double? slippage,
    rpc.RoutedSwapOrder? order,
    String? provider,
  }) async {
    if (balance <= Decimal.zero) {
      return RoutedSwapMaxSell(
        amount: Decimal.zero,
        reservedForFees: Decimal.zero,
        feeAsset: from.parentId ?? from,
      );
    }
    if (from.isChildAsset) {
      return RoutedSwapMaxSell(
        amount: balance,
        reservedForFees: Decimal.zero,
        feeAsset: from.parentId,
      );
    }

    final probe = await quote(
      from: from,
      to: to,
      amount: balance,
      slippage: slippage,
      order: order,
      provider: provider,
    );
    final gas = probe.networkFees
        .where((fee) => fee.assetId == from || fee.ticker == from.id)
        .fold<Decimal>(Decimal.zero, (sum, fee) => sum + fee.amount);

    final decimals = from.chainId.decimals;
    var reserve = gas * maxSellFeeMargin;
    var amount = balance - reserve;
    if (decimals != null) {
      reserve = reserve.ceil(scale: decimals);
      amount = (balance - reserve).floor(scale: decimals);
    }
    if (amount < Decimal.zero) amount = Decimal.zero;

    return RoutedSwapMaxSell(
      amount: amount,
      reservedForFees: reserve,
      feeAsset: from,
    );
  }

  /// Starts a swap and returns a handle whose [RoutedSwapHandle.uuid] is
  /// already resolved.
  ///
  /// The guard sent to KDF is the offer's guaranteed receive, so a swap can
  /// never be started against a number the user was not shown, and the
  /// offer's route order is passed on so the engine's internal re-quote
  /// targets the same route.
  ///
  /// Throws the typed [rpc.RoutedSwapRpcException] when KDF rejects the
  /// request before creating a task — nothing started. Throws
  /// [RoutedSwapStartUnconfirmedException] when the swap may have started but
  /// its durable id could not be read back: never retry on that; check
  /// history.
  Future<RoutedSwapHandle> start(RoutedSwapOffer offer) async {
    final startedAt = DateTime.now();
    final rpc.RoutedSwapInitResponse init;
    try {
      init = await _client.rpc.routedSwap.init(
        from: offer.from.id,
        to: offer.to.id,
        amount: offer.sellAmount.toString(),
        minToAmount: offer.guaranteedReceive.toString(),
        slippage: offer.slippage,
        order: offer.order,
        provider: offer.provider,
      );
    } on rpc.RoutedSwapRpcException {
      // A typed rejection comes back before any task exists.
      rethrow;
    } on Object catch (error) {
      // The request may have reached KDF and created the task.
      throw RoutedSwapStartUnconfirmedException(error);
    }

    // Resolve the uuid before handing back a handle. Everything after this
    // point is recoverable; the window before it is not, so it is closed here
    // rather than left to each caller.
    Object? lastError;
    for (var attempt = 0; attempt < _firstReadAttempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_firstReadRetryDelay * attempt);
      }
      try {
        final first = await _client.rpc.routedSwap.status(init.taskId);
        final seed = _progressFromStatus(first.details, accepted: offer);
        final session = _RoutedSwapSession(
          manager: this,
          uuid: first.details.uuid,
          taskId: init.taskId,
          offer: offer,
          seed: seed,
        ).._lastLivePhase = seed.isTerminal ? null : seed.phase;
        return _register(session);
      } on Object catch (error) {
        lastError = error;
      }
    }

    // KDF persists the uuid before the task starts executing, so the durable
    // record can still identify the swap this request created.
    final entry = await _findStartedEntry(offer, since: startedAt);
    if (entry == null) {
      throw RoutedSwapStartUnconfirmedException(
        lastError ?? StateError('No status for task ${init.taskId}'),
        taskId: init.taskId,
      );
    }
    final session = _RoutedSwapSession(
      manager: this,
      uuid: entry.uuid,
      taskId: init.taskId,
      offer: offer,
      seed: _progressFromEntry(entry, accepted: offer),
    );
    return _register(session);
  }

  /// Re-attaches to a swap by its durable id.
  ///
  /// Returns the live session when one is running in this process, and
  /// otherwise a handle that follows the persisted record — so a screen opened
  /// after a restart behaves the same as one that never closed.
  ///
  /// Throws [RoutedSwapNotFoundException] when nothing is known about [uuid].
  Future<RoutedSwapHandle> watch(String uuid) async {
    final live = _sessions[uuid];
    if (live != null && !live.isDisposed) return _RoutedSwapHandle(live);

    final entry = await _entryFor(uuid);
    if (entry == null) throw RoutedSwapNotFoundException(uuid);

    // A swap KDF is still tracking after a restart has no task id any client
    // can hold, so history polling is the only way to follow it.
    final session = _RoutedSwapSession(
      manager: this,
      uuid: uuid,
      seed: _progressFromEntry(entry),
    );
    return _register(session);
  }

  /// Swaps that have not finished, newest first, across every page.
  ///
  /// The cold-start question: after a relaunch, what is still running? A
  /// 30-minute bridge outlives most app sessions, so this is the normal path.
  Future<List<RoutedSwapProgress>> inFlight({int pageSize = 50}) async {
    final entries = <RoutedSwapProgress>[];
    for (var page = 1; page <= 20; page++) {
      final result = await history(
        filter: rpc.RoutedSwapHistoryFilter.inFlight,
        limit: pageSize,
        pageNumber: page,
      );
      entries.addAll(result.entries);
      if (!result.hasMore) break;
    }
    return entries;
  }

  /// Past and present swaps, newest first.
  Future<RoutedSwapHistoryPage> history({
    int pageNumber = 1,
    int limit = 20,
    rpc.RoutedSwapHistoryFilter? filter,
    AssetId? from,
    AssetId? to,
    DateTime? createdAfter,
    DateTime? createdBefore,
  }) async {
    final page = await _client.rpc.routedSwap.history(
      filter: filter,
      myCoin: from?.id,
      otherCoin: to?.id,
      fromTimestamp: createdAfter == null ? null : _unixSeconds(createdAfter),
      toTimestamp: createdBefore == null ? null : _unixSeconds(createdBefore),
      limit: limit,
      pageNumber: pageNumber,
    );
    return RoutedSwapHistoryPage(
      entries: [
        for (final entry in page.entries)
          _progressFromEntry(
            entry,
            accepted: _sessions[entry.uuid]?.offer,
            previous: _sessions[entry.uuid]?.latest,
            lastLivePhase: _sessions[entry.uuid]?.lastLivePhase,
          ),
      ],
      total: page.total,
      pageNumber: page.pageNumber,
      totalPages: page.totalPages,
    );
  }

  /// Releases every live session.
  Future<void> dispose() async {
    final sessions = _sessions.values.toList();
    _sessions.clear();
    for (final session in sessions) {
      await session.dispose();
    }
  }

  // ------------------------------------------------------------- internals

  RoutedSwapHandle _register(_RoutedSwapSession session) {
    final existing = _sessions[session.uuid];
    if (existing != null && !existing.isDisposed) {
      unawaited(session.dispose());
      return _RoutedSwapHandle(existing);
    }
    _sessions[session.uuid] = session;
    session.start();
    return _RoutedSwapHandle(session);
  }

  Future<rpc.RoutedSwapHistoryEntry?> _entryFor(String uuid) async {
    final page = await _client.rpc.routedSwap.history(uuid: uuid, limit: 1);
    return page.entries.isEmpty ? null : page.entries.first;
  }

  /// Finds the record `init` created for [offer] when its task could not be
  /// read back.
  Future<rpc.RoutedSwapHistoryEntry?> _findStartedEntry(
    RoutedSwapOffer offer, {
    required DateTime since,
  }) async {
    try {
      final page = await _client.rpc.routedSwap.history(
        myCoin: offer.from.id,
        otherCoin: offer.to.id,
        fromTimestamp: _unixSeconds(since) - 5,
        limit: 10,
      );
      for (final entry in page.entries) {
        final amount = Decimal.tryParse(entry.requested.amount);
        final minimum = Decimal.tryParse(entry.minToAmountAccepted);
        if (amount == offer.sellAmount &&
            minimum == offer.guaranteedReceive &&
            !_sessions.containsKey(entry.uuid)) {
          return entry;
        }
      }
    } on Object {
      // The caller reports the start as unconfirmed.
    }
    return null;
  }

  static int _unixSeconds(DateTime time) =>
      time.toUtc().millisecondsSinceEpoch ~/ 1000;

  static DateTime? _fromUnix(int? seconds) => seconds == null || seconds == 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

  Decimal? _decimal(String? value) =>
      value == null ? null : Decimal.tryParse(value);

  RoutedSwapOffer _offerFrom(
    rpc.RoutedSwapRoute route, {
    required AssetId from,
    required AssetId to,
    rpc.RoutedSwapOrder? order,
    double? slippage,
    DateTime? quotedAt,
  }) {
    RoutedSwapCost gasCost(
      rpc.RoutedSwapGasCost gas,
      RoutedSwapCostKind kind,
    ) => RoutedSwapCost(
      label: kind == RoutedSwapCostKind.approvalGas
          ? 'Approval network fee'
          : 'Network fee',
      amount: Decimal.parse(gas.amount.amount),
      kind: kind,
      isDeductedFromReceive: false,
      assetId: gas.amount.coin == null ? null : _resolveAsset(gas.amount.coin!),
      symbol: gas.amount.symbol,
      usdValue: _decimal(gas.amountUsd),
    );

    final costs = <RoutedSwapCost>[
      for (final fee in route.feeCosts)
        RoutedSwapCost(
          label: fee.name,
          amount: Decimal.parse(fee.amount.amount),
          kind: RoutedSwapCostKind.providerFee,
          isDeductedFromReceive: fee.included,
          assetId: fee.amount.coin == null
              ? null
              : _resolveAsset(fee.amount.coin!),
          symbol: fee.amount.symbol,
          usdValue: _decimal(fee.amountUsd),
        ),
      for (final gas in route.gasCosts) gasCost(gas, RoutedSwapCostKind.gas),
      for (final gas
          in route.approval?.gasCosts ?? const <rpc.RoutedSwapGasCost>[])
        gasCost(gas, RoutedSwapCostKind.approvalGas),
    ];

    final approval = route.approval;
    return RoutedSwapOffer(
      from: from,
      to: to,
      sellAmount: Decimal.parse(route.from.amount),
      expectedReceive: Decimal.parse(route.to.amount),
      guaranteedReceive: Decimal.parse(route.toMinimum.amount),
      kind: route.kind,
      costs: costs,
      networkFees: _networkFeesOf(route),
      legs: [
        for (final step in route.steps)
          RoutedSwapLeg(
            type: step.stepType,
            chainId: step.chainId,
            fromChainId: step.fromChainId,
            toChainId: step.toChainId,
          ),
      ],
      quotedAt: quotedAt ?? DateTime.now(),
      provider: route.provider,
      toolKey: route.tool.key,
      toolName: route.tool.name,
      toolLogoUrl: route.tool.logoUrl,
      route: route,
      order: order,
      fromAddress: route.fromAddress,
      toAddress: route.toAddress,
      approval: approval == null
          ? null
          : RoutedSwapApprovalInfo(
              txCount: approval.txCount,
              resetsFirst: approval.resetsFirst,
              spender: approval.spender,
            ),
      estimatedDuration: route.executionDurationS == null
          ? null
          : Duration(seconds: route.executionDurationS!),
      slippage: slippage,
    );
  }

  /// The per-coin network fee. Uses the engine's totals when present, and
  /// otherwise sums execution and approval gas the same way — a USD value
  /// only when every contributing row has one.
  List<RoutedSwapNetworkFee> _networkFeesOf(rpc.RoutedSwapRoute route) {
    final rows = route.totalGasCosts.isNotEmpty
        ? route.totalGasCosts
        : [...route.gasCosts, ...?route.approval?.gasCosts];
    final amounts = <String, Decimal>{};
    final usd = <String, Decimal?>{};
    for (final row in rows) {
      final ticker = row.amount.label;
      amounts[ticker] =
          (amounts[ticker] ?? Decimal.zero) + Decimal.parse(row.amount.amount);
      final rowUsd = _decimal(row.amountUsd);
      usd[ticker] = !usd.containsKey(ticker)
          ? rowUsd
          : (usd[ticker] == null || rowUsd == null
                ? null
                : usd[ticker]! + rowUsd);
    }
    return [
      for (final entry in amounts.entries)
        RoutedSwapNetworkFee(
          ticker: entry.key,
          assetId: _resolveAsset(entry.key),
          amount: entry.value,
          usdValue: usd[entry.key],
        ),
    ];
  }

  RoutedSwapOffer? _offerFromExecuted(
    rpc.RoutedSwapRoute? route,
    RoutedSwapOffer? accepted, {
    RoutedSwapOffer? previous,
  }) {
    if (route == null) return null;
    // Every poll re-reports the same executed route. Reusing the offer built
    // from it keeps snapshots equal, so an unchanged swap does not re-emit.
    if (previous != null && previous.route == route) return previous;
    final from = accepted?.from ?? _resolveAssetOf(route.from);
    final to = accepted?.to ?? _resolveAssetOf(route.toMinimum);
    if (from == null || to == null) return null;
    return _offerFrom(
      route,
      from: from,
      to: to,
      order: accepted?.order,
      slippage: accepted?.slippage,
      quotedAt: accepted?.quotedAt ?? previous?.quotedAt,
    );
  }

  AssetId? _resolveAssetOf(rpc.RoutedSwapAmount amount) =>
      amount.coin == null ? null : _resolveAsset(amount.coin!);

  RoutedSwapProgress _progressFromStatus(
    rpc.RoutedSwapStatus status, {
    RoutedSwapOffer? accepted,
    RoutedSwapOffer? previousExecuted,
    List<String> approvalTxHashes = const [],
    RoutedSwapPhase? lastLivePhase,
    bool fromHistory = false,
  }) {
    final executed = _offerFromExecuted(
      status.executedRoute,
      accepted,
      previous: previousExecuted,
    );
    switch (status) {
      case rpc.RoutedSwapInProgress():
        final hashes = [
          ...approvalTxHashes,
          if (status.approveTxHash != null &&
              !approvalTxHashes.contains(status.approveTxHash))
            status.approveTxHash!,
        ];
        return RoutedSwapProgress(
          uuid: status.uuid,
          provider: status.provider,
          phase: _phaseOf(status.state),
          // A record recovered from history has no addressable task, so there
          // is nothing to cancel even when the phase would otherwise allow it.
          canCancel: !fromHistory && status.state.isCancellable,
          rawState: status.rawState,
          bridgeStage: status.stage,
          acceptedOffer: accepted,
          executedOffer: executed,
          approvalTxHashes: hashes,
          sourceTxHash: status.sourceTxHash,
          explorerUrl: status.providerExplorerUrl,
          providerStatusDetail: status.substatusMessage ?? status.substatus,
          estimatedDuration: status.executionDurationS == null
              ? executed?.estimatedDuration
              : Duration(seconds: status.executionDurationS!),
          actionUrl: status.actionUrl,
        );
      case rpc.RoutedSwapFinished():
        return RoutedSwapProgress(
          uuid: status.uuid,
          provider: status.provider,
          phase: RoutedSwapPhase.finished,
          canCancel: false,
          acceptedOffer: accepted,
          executedOffer: executed,
          receipt: RoutedSwapReceipt(
            outcome: status.outcome,
            partialReason: status.partialReason,
            amount: Decimal.parse(status.received.amount),
            assetId: _resolveAssetOf(status.received),
            symbol: status.received.symbol,
          ),
          approvalTxHashes: approvalTxHashes,
          sourceTxHash: status.sourceTxHash,
          destinationTxHash: status.destTxHash,
          explorerUrl: status.providerExplorerUrl,
        );
      case rpc.RoutedSwapErrored():
        final failure = _failureFrom(
          status,
          accepted: accepted ?? executed,
          approvalTxHashes: approvalTxHashes,
          lastLivePhase: lastLivePhase,
        );
        return RoutedSwapProgress(
          uuid: status.uuid,
          provider: status.provider,
          phase: RoutedSwapPhase.failed,
          canCancel: false,
          acceptedOffer: accepted,
          executedOffer: executed,
          failure: failure,
          approvalTxHashes: approvalTxHashes,
          sourceTxHash: failure.sourceTxHash,
          explorerUrl: failure.providerExplorerUrl,
        );
    }
  }

  RoutedSwapProgress _progressFromEntry(
    rpc.RoutedSwapHistoryEntry entry, {
    RoutedSwapOffer? accepted,
    RoutedSwapProgress? previous,
    RoutedSwapPhase? lastLivePhase,
  }) {
    final hashes = entry.approvalTxHashes.isNotEmpty
        ? entry.approvalTxHashes
        : previous?.approvalTxHashes ?? const <String>[];
    final base = _progressFromStatus(
      entry.swap,
      accepted: accepted,
      previousExecuted: previous?.executedOffer,
      approvalTxHashes: hashes,
      // Only a phase this process watched live can prove a failure happened
      // before broadcast.
      lastLivePhase: lastLivePhase,
      fromHistory: true,
    );
    final requested = entry.requested;
    return base.copyWith(
      approvalTxHashes: hashes,
      createdAt: _fromUnix(entry.createdAt),
      updatedAt: _fromUnix(entry.updatedAt),
      finishedAt: _fromUnix(entry.finishedAt),
      requested: RoutedSwapRequest(
        fromTicker: requested.from,
        toTicker: requested.to,
        from: _resolveAsset(requested.from),
        to: _resolveAsset(requested.to),
        amount: Decimal.tryParse(requested.amount) ?? Decimal.zero,
      ),
      minToAmountAccepted: _decimal(entry.minToAmountAccepted),
      gasSpent: [
        for (final gas in entry.gasSpent)
          RoutedSwapGasPaid(
            txHash: gas.txHash.isEmpty ? null : gas.txHash,
            ticker: gas.coin,
            assetId: _resolveAsset(gas.coin),
            amount: Decimal.tryParse(gas.amount) ?? Decimal.zero,
          ),
      ],
      totalGasSpent: [
        for (final gas in entry.totalGasSpent)
          RoutedSwapGasPaid(
            ticker: gas.coin,
            assetId: _resolveAsset(gas.coin),
            amount: Decimal.tryParse(gas.amount) ?? Decimal.zero,
          ),
      ],
    );
  }

  RoutedSwapFailure _failureFrom(
    rpc.RoutedSwapErrored status, {
    required List<String> approvalTxHashes,
    RoutedSwapOffer? accepted,
    RoutedSwapPhase? lastLivePhase,
  }) {
    final error = status.error;
    final kind = switch (error) {
      rpc.RoutedSwapQuoteWorsenedError() => RoutedSwapFailureKind.priceMoved,
      rpc.RoutedSwapInsufficientBalanceError() =>
        RoutedSwapFailureKind.insufficientBalance,
      rpc.RoutedSwapApprovalFailedError() =>
        RoutedSwapFailureKind.approvalFailed,
      rpc.RoutedSwapTxFailedError() =>
        RoutedSwapFailureKind.swapTransactionFailed,
      rpc.RoutedSwapSigningRejectedError() =>
        RoutedSwapFailureKind.signingRejected,
      rpc.RoutedSwapBridgeFailedError() => RoutedSwapFailureKind.bridgeFailed,
      rpc.RoutedSwapPreflightRejectedError() =>
        RoutedSwapFailureKind.preflightRejected,
      rpc.RoutedSwapNoRouteTaskError() ||
      rpc.RoutedSwapRateLimitedTaskError() ||
      rpc.RoutedSwapProviderTaskError() ||
      rpc.RoutedSwapAmountOutOfBoundsTaskError() =>
        RoutedSwapFailureKind.quoteUnavailable,
      rpc.RoutedSwapAbortedOnRestartError() =>
        RoutedSwapFailureKind.abortedOnRestart,
      rpc.RoutedSwapTaskCancelledError() => RoutedSwapFailureKind.cancelled,
      rpc.RoutedSwapInternalTaskError() ||
      rpc.RoutedSwapTransportTaskError() => RoutedSwapFailureKind.internalError,
      rpc.RoutedSwapUnknownTaskError() => RoutedSwapFailureKind.unknown,
    };

    final movement = _fundsMovementOf(
      error,
      approved: approvalTxHashes.isNotEmpty,
      lastLivePhase: lastLivePhase,
    );

    RoutedSwapOffer? freshOffer;
    if (error case rpc.RoutedSwapQuoteWorsenedError(:final freshRoute?)) {
      final from = accepted?.from ?? _resolveAssetOf(freshRoute.from);
      final to = accepted?.to ?? _resolveAssetOf(freshRoute.toMinimum);
      if (from != null && to != null) {
        freshOffer = _offerFrom(
          freshRoute,
          from: from,
          to: to,
          order: accepted?.order,
          slippage: accepted?.slippage,
        );
      }
    }

    return RoutedSwapFailure(
      kind: kind,
      errorType: status.errorType,
      message: status.message,
      fundsMovement: movement,
      retryPolicy: _retryPolicyOf(error, movement),
      details: switch (error) {
        rpc.RoutedSwapUnknownTaskError(:final data) => data,
        _ => const {},
      },
      freshOffer: freshOffer,
      approvalFailureReason: switch (error) {
        rpc.RoutedSwapApprovalFailedError(:final reason) => reason,
        _ => null,
      },
      txFailureReason: switch (error) {
        rpc.RoutedSwapTxFailedError(:final reason) => reason,
        _ => null,
      },
      signingRejectionReason: switch (error) {
        rpc.RoutedSwapSigningRejectedError(:final reason) => reason,
        _ => null,
      },
      preflightCheck: switch (error) {
        rpc.RoutedSwapPreflightRejectedError(:final check) => check,
        _ => null,
      },
      shortfall: switch (error) {
        rpc.RoutedSwapInsufficientBalanceError(
          :final coin,
          :final available,
          :final required,
        ) =>
          RoutedSwapShortfall(
            ticker: coin,
            assetId: _resolveAsset(coin),
            available: Decimal.tryParse(available) ?? Decimal.zero,
            required: Decimal.tryParse(required) ?? Decimal.zero,
          ),
        _ => null,
      },
      bounds: switch (error) {
        rpc.RoutedSwapAmountOutOfBoundsTaskError(:final min, :final max) =>
          RoutedSwapAmountBounds(min: _decimal(min), max: _decimal(max)),
        _ => null,
      },
      noRouteReasons: switch (error) {
        rpc.RoutedSwapNoRouteTaskError(:final reasons) => reasons,
        _ => const [],
      },
      providerRequestId: error.providerRequestId,
      sourceTxHash: switch (error) {
        rpc.RoutedSwapTxFailedError(:final sourceTxHash) => sourceTxHash,
        rpc.RoutedSwapBridgeFailedError(:final sourceTxHash) => sourceTxHash,
        _ => null,
      },
      providerExplorerUrl: switch (error) {
        rpc.RoutedSwapBridgeFailedError(:final providerExplorerUrl) =>
          providerExplorerUrl,
        _ => null,
      },
    );
  }

  /// Whether the sold funds moved, never claiming "untouched" without proof.
  static RoutedSwapFundsMovement _fundsMovementOf(
    rpc.RoutedSwapTaskError error, {
    required bool approved,
    RoutedSwapPhase? lastLivePhase,
  }) {
    final untouched = approved
        ? RoutedSwapFundsMovement.feesOnly
        : RoutedSwapFundsMovement.none;
    final watchedBeforeBroadcast =
        lastLivePhase != null && _isPreBroadcast(lastLivePhase);

    switch (error) {
      case rpc.RoutedSwapTxFailedError(:final reason):
        return reason == rpc.RoutedSwapTxFailureReason.sourceTransactionReverted
            ? RoutedSwapFundsMovement.feesOnly
            : RoutedSwapFundsMovement.uncertain;
      case rpc.RoutedSwapBridgeFailedError():
        return RoutedSwapFundsMovement.sent;
      case rpc.RoutedSwapApprovalFailedError(:final reason):
        // The swap never went out; an approval or reset may still have cost
        // gas.
        return !approved &&
                reason ==
                    rpc.RoutedSwapApprovalFailureReason.approvalBroadcastFailed
            ? RoutedSwapFundsMovement.none
            : RoutedSwapFundsMovement.feesOnly;
      case rpc.RoutedSwapSigningRejectedError(:final reason):
        if (reason != rpc.RoutedSwapSigningRejectionReason.timeout) {
          return untouched;
        }
        return watchedBeforeBroadcast
            ? untouched
            : RoutedSwapFundsMovement.uncertain;
      case rpc.RoutedSwapInternalTaskError():
        // Rare, but it can follow an uncertain wallet handoff after
        // Broadcasting; only a live observation before broadcast rules that
        // out.
        return watchedBeforeBroadcast
            ? untouched
            : RoutedSwapFundsMovement.uncertain;
      case rpc.RoutedSwapUnknownTaskError():
        return RoutedSwapFundsMovement.uncertain;
      default:
        return error.isPreBroadcast
            ? untouched
            : RoutedSwapFundsMovement.uncertain;
    }
  }

  static bool _isPreBroadcast(RoutedSwapPhase phase) =>
      phase == RoutedSwapPhase.preparing ||
      phase == RoutedSwapPhase.approving ||
      phase == RoutedSwapPhase.signing;

  static RoutedSwapRetryPolicy _retryPolicyOf(
    rpc.RoutedSwapTaskError error,
    RoutedSwapFundsMovement movement,
  ) {
    return switch (error) {
      rpc.RoutedSwapQuoteWorsenedError() => RoutedSwapRetryPolicy.requote,
      rpc.RoutedSwapInsufficientBalanceError() =>
        RoutedSwapRetryPolicy.fixAndRetry,
      rpc.RoutedSwapApprovalFailedError() => RoutedSwapRetryPolicy.retry,
      rpc.RoutedSwapTxFailedError(:final reason) =>
        reason == rpc.RoutedSwapTxFailureReason.sourceTransactionReverted
            ? RoutedSwapRetryPolicy.requote
            : RoutedSwapRetryPolicy.wait,
      rpc.RoutedSwapSigningRejectedError() =>
        movement == RoutedSwapFundsMovement.uncertain
            ? RoutedSwapRetryPolicy.wait
            : RoutedSwapRetryPolicy.retry,
      rpc.RoutedSwapBridgeFailedError() => RoutedSwapRetryPolicy.contactSupport,
      rpc.RoutedSwapPreflightRejectedError(:final check) =>
        check.isRetryable
            ? RoutedSwapRetryPolicy.retry
            : check.mayPassOnRequote
            ? RoutedSwapRetryPolicy.requote
            : RoutedSwapRetryPolicy.contactSupport,
      rpc.RoutedSwapRateLimitedTaskError() ||
      rpc.RoutedSwapProviderTaskError() => RoutedSwapRetryPolicy.retry,
      rpc.RoutedSwapNoRouteTaskError() ||
      rpc.RoutedSwapAmountOutOfBoundsTaskError() =>
        RoutedSwapRetryPolicy.requote,
      rpc.RoutedSwapAbortedOnRestartError() ||
      rpc.RoutedSwapTaskCancelledError() => RoutedSwapRetryPolicy.retry,
      rpc.RoutedSwapInternalTaskError() || rpc.RoutedSwapTransportTaskError() =>
        movement == RoutedSwapFundsMovement.uncertain
            ? RoutedSwapRetryPolicy.contactSupport
            : RoutedSwapRetryPolicy.retry,
      rpc.RoutedSwapUnknownTaskError() => RoutedSwapRetryPolicy.contactSupport,
    };
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

class _RoutedSwapHandle implements RoutedSwapHandle {
  _RoutedSwapHandle(this._session);

  final _RoutedSwapSession _session;

  @override
  String get uuid => _session.uuid;

  @override
  RoutedSwapProgress get latest => _session.latest;

  @override
  Stream<RoutedSwapProgress> get progress => _session.stream;

  @override
  Future<RoutedSwapProgress> get result => _session.result;

  @override
  Future<void> cancel() => _session.cancel();
}

/// Follows one swap: its task while it exists, polled as the truth with the
/// event stream as a nudge, and the durable record once the task is gone.
///
/// Runs independently of listeners — a screen closing must not stop a swap
/// from being followed — until the swap is terminal.
class _RoutedSwapSession {
  _RoutedSwapSession({
    required RoutedSwapManager manager,
    required this.uuid,
    required RoutedSwapProgress seed,
    int? taskId,
    this.offer,
  }) : _manager = manager,
       _taskId = taskId,
       _latest = seed;

  final RoutedSwapManager _manager;
  final String uuid;

  /// The offer the user accepted, for swaps started in this process.
  final RoutedSwapOffer? offer;

  int? _taskId;
  RoutedSwapProgress _latest;

  /// The last phase read from the live task — the only kind of observation
  /// that can prove a later failure happened before broadcast.
  RoutedSwapPhase? _lastLivePhase;
  final StreamController<RoutedSwapProgress> _updates =
      StreamController<RoutedSwapProgress>.broadcast();
  final Completer<RoutedSwapProgress> _result = Completer<RoutedSwapProgress>();

  Timer? _timer;
  StreamSubscription<void>? _nudges;
  var _refreshing = false;
  var _failures = 0;
  var _disposed = false;

  RoutedSwapProgress get latest => _latest;

  RoutedSwapPhase? get lastLivePhase => _lastLivePhase;

  bool get isDisposed => _disposed;

  Future<RoutedSwapProgress> get result => _result.future;

  Stream<RoutedSwapProgress> get stream => Stream.multi((out) {
    out.add(_latest);
    if (_updates.isClosed) {
      unawaited(out.close());
      return;
    }
    final subscription = _updates.stream.listen(
      out.add,
      onError: out.addError,
      onDone: out.close,
    );
    out.onCancel = subscription.cancel;
  });

  void start() {
    if (_latest.isTerminal) {
      final taskId = _taskId;
      if (taskId == null) {
        _finish();
      } else {
        unawaited(_settleTerminalSeed(taskId));
      }
      return;
    }
    final taskId = _taskId;
    if (taskId != null) {
      try {
        _nudges = _manager._taskNudges
            ?.call(taskId)
            .listen((_) => _refreshSoon(), onError: (_) {});
      } on Object {
        // A stream that will not start is not worth surfacing; polling covers
        // it.
      }
    }
    _schedule(_taskId != null ? _manager._pollInterval : Duration.zero);
  }

  void _refreshSoon() {
    if (_refreshing || _disposed || _latest.isTerminal) return;
    _timer?.cancel();
    unawaited(_refresh());
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (_disposed || _latest.isTerminal) return;
    _timer = Timer(delay, () => unawaited(_refresh()));
  }

  Future<void> _refresh() async {
    if (_refreshing || _disposed || _latest.isTerminal) return;
    _refreshing = true;
    var next = _taskId != null
        ? _manager._pollInterval
        : _manager._historyPollInterval;
    try {
      if (_taskId != null) {
        await _refreshFromTask(_taskId!);
      } else {
        await _refreshFromHistory();
      }
      _failures = 0;
      if (_latest.delayedSince != null && !_latest.isTerminal) {
        _emit(_latest.copyWith(clearDelayedSince: true));
      }
    } on rpc.RoutedSwapNoSuchTaskException {
      // The task is gone — cancelled, forgotten, or lost to a restart. The
      // swap itself may be entirely fine; the durable record decides.
      _taskId = null;
      next = Duration.zero;
    } on Object {
      _failures++;
      next = _backoff(next);
      if (_failures >= _manager._delayedAfterFailures &&
          _latest.delayedSince == null) {
        _emit(_latest.copyWith(delayedSince: DateTime.now()));
      }
    } finally {
      _refreshing = false;
    }
    if (_latest.isTerminal) {
      _finish();
    } else {
      _schedule(next);
    }
  }

  Duration _backoff(Duration base) {
    final factor = math.pow(2, math.min(_failures, 5)).toInt();
    final delay = base * factor;
    return delay > _manager._maxBackoff ? _manager._maxBackoff : delay;
  }

  Future<void> _refreshFromTask(int taskId) async {
    final response = await _manager._client.rpc.routedSwap.status(taskId);
    // KDF numbers tasks from zero again after a restart, so this id can now
    // belong to a different swap. Treat it as gone; history decides.
    if (response.details.uuid != uuid) {
      throw rpc.RoutedSwapNoSuchTaskException(
        message: 'Task $taskId now belongs to another swap',
        taskId: taskId,
      );
    }
    final progress = _manager._progressFromStatus(
      response.details,
      accepted: offer,
      previousExecuted: _latest.executedOffer,
      approvalTxHashes: _latest.approvalTxHashes,
      lastLivePhase: _lastLivePhase,
    );
    if (!progress.isTerminal) {
      _lastLivePhase = progress.phase;
      _emit(progress);
      return;
    }
    _emit(await _enriched(progress));
    unawaited(_forget(taskId));
  }

  /// [terminal], completed from the durable record — timestamps, every
  /// approval, the gas actually spent — when the record has caught up.
  Future<RoutedSwapProgress> _enriched(RoutedSwapProgress terminal) async {
    try {
      final entry = await _manager._entryFor(uuid);
      if (entry != null && entry.swap.isTerminal) {
        return _manager._progressFromEntry(
          entry,
          accepted: offer,
          previous: terminal,
          lastLivePhase: _lastLivePhase,
        );
      }
    } on Object {
      // The live terminal result stands on its own.
    }
    return terminal;
  }

  /// A swap whose very first read was already terminal still gets the
  /// durable record's details, and its task is still released.
  Future<void> _settleTerminalSeed(int taskId) async {
    _emit(await _enriched(_latest));
    await _forget(taskId);
    _finish();
  }

  Future<void> _refreshFromHistory() async {
    final entry = await _manager._entryFor(uuid);
    if (entry == null) throw RoutedSwapNotFoundException(uuid);
    _emit(
      _manager._progressFromEntry(
        entry,
        accepted: offer,
        previous: _latest,
        lastLivePhase: _lastLivePhase,
      ),
    );
  }

  /// Releases the finished task. The result has been read and emitted, and
  /// the durable record keeps it.
  Future<void> _forget(int taskId) async {
    _taskId = null;
    try {
      await _manager._client.rpc.routedSwap.status(
        taskId,
        forgetIfFinished: true,
      );
    } on Object {
      // Already gone is the same outcome.
    }
  }

  void _emit(RoutedSwapProgress progress) {
    if (_disposed || _updates.isClosed) return;
    if (progress == _latest) return;
    _latest = progress;
    _updates.add(progress);
    if (progress.isTerminal) _finish();
  }

  void _finish() {
    _timer?.cancel();
    _timer = null;
    unawaited(_nudges?.cancel());
    _nudges = null;
    if (!_result.isCompleted) _result.complete(_latest);
    if (!_updates.isClosed) unawaited(_updates.close());
  }

  Future<void> cancel() async {
    final taskId = _taskId;
    if (_latest.isTerminal) {
      throw RoutedSwapNotCancellableException(
        uuid,
        _latest.phase,
        refusal: RoutedSwapCancelRefusal.alreadyFinished,
      );
    }
    if (taskId == null) {
      throw RoutedSwapNotCancellableException(
        uuid,
        _latest.phase,
        refusal: RoutedSwapCancelRefusal.notAddressable,
      );
    }
    if (!_latest.canCancel) {
      throw RoutedSwapNotCancellableException(uuid, _latest.phase);
    }

    try {
      await _manager._client.rpc.routedSwap.cancel(taskId);
    } on rpc.RoutedSwapTaskAlreadyBroadcastException {
      _refreshSoon();
      throw RoutedSwapNotCancellableException(uuid, RoutedSwapPhase.sending);
    } on rpc.RoutedSwapTaskFinishedException {
      _refreshSoon();
      throw RoutedSwapNotCancellableException(
        uuid,
        _latest.phase,
        refusal: RoutedSwapCancelRefusal.alreadyFinished,
      );
    } on rpc.RoutedSwapNoSuchTaskException {
      // Gone already — an earlier cancel may have landed. The durable record
      // says whether this one is moot or impossible.
      _taskId = null;
      await _refreshNow();
      if (_latest.failure?.kind == RoutedSwapFailureKind.cancelled) return;
      throw RoutedSwapNotCancellableException(
        uuid,
        _latest.phase,
        refusal: _latest.isTerminal
            ? RoutedSwapCancelRefusal.alreadyFinished
            : RoutedSwapCancelRefusal.notAddressable,
      );
    } on Object catch (error) {
      _refreshSoon();
      throw RoutedSwapCancelUnconfirmedException(uuid, error);
    }

    // Accepted: the task is removed and history records the cancellation.
    _taskId = null;
    await _refreshNow();
  }

  Future<void> _refreshNow() async {
    _timer?.cancel();
    while (_refreshing) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await _refresh();
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await _nudges?.cancel();
    _nudges = null;
    if (!_updates.isClosed) await _updates.close();
  }
}
