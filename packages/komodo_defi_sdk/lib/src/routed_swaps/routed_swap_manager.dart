import 'dart:async';
import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;
import 'package:komodo_defi_sdk/src/routed_swaps/routed_swap_types.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

part 'routed_swap_manager_offers.dart';
part 'routed_swap_manager_progress.dart';
part 'routed_swap_session.dart';

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
  /// The probe reports the provider's gas estimate at today's price, but
  /// KDF checks the balance at start against the route's gas limit at its
  /// own maximum fee per gas, which runs well above that. A reserve short of
  /// KDF's figure fails the start, so the margin is generous: leftover dust
  /// is the cheaper failure.
  static final Decimal maxSellFeeMargin = Decimal.parse('3');

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
}
