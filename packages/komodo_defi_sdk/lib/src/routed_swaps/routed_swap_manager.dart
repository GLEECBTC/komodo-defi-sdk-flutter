import 'dart:async';
import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
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

  /// When KDF last answered for this swap, whether or not anything changed;
  /// null until it has. [progress] carries only changes, so this is what
  /// tells a quiet swap from one KDF has stopped answering for.
  DateTime? get checkedAt;

  /// [checkedAt], as each answer arrives, until the swap is terminal.
  Stream<DateTime> get checks;

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
    required KomodoDefiLocalAuth auth,
    required RoutedSwapAssetResolver resolveAsset,
    RoutedSwapTaskNudges? taskNudges,
    Duration pollInterval = const Duration(seconds: 3),
    Duration historyPollInterval = const Duration(seconds: 5),
    Duration maxBackoff = const Duration(seconds: 30),
    int delayedAfterFailures = 3,
    Duration firstReadRetryDelay = const Duration(milliseconds: 500),
    int firstReadAttempts = 3,
    DateTime Function()? now,
  }) : _client = client,
       _auth = auth,
       _resolveAsset = resolveAsset,
       _taskNudges = taskNudges,
       _pollInterval = pollInterval,
       _historyPollInterval = historyPollInterval,
       _maxBackoff = maxBackoff,
       _delayedAfterFailures = delayedAfterFailures,
       _firstReadRetryDelay = firstReadRetryDelay,
       _firstReadAttempts = firstReadAttempts,
       _now = now ?? DateTime.now;

  final ApiClient _client;
  final KomodoDefiLocalAuth _auth;
  AuthSessionContext? _walletSession;
  StreamSubscription<AuthSessionContext?>? _authSubscription;
  bool _disposed = false;
  final RoutedSwapAssetResolver _resolveAsset;
  final RoutedSwapTaskNudges? _taskNudges;
  final Duration _pollInterval;
  final Duration _historyPollInterval;
  final Duration _maxBackoff;
  final int _delayedAfterFailures;
  final Duration _firstReadRetryDelay;
  final int _firstReadAttempts;
  final DateTime Function() _now;

  final Map<String, _RoutedSwapSession> _sessions = {};

  Future<AuthSessionContext> _captureSession() async {
    if (_disposed) throw const AuthSessionChangedException();
    _authSubscription ??= _auth.watchSessionContext().listen(
      _observeSession,
      onError: (Object _) => _clearSessions(),
    );
    final context = await _auth.captureSessionContext();
    _requireCurrent(context);
    _observeSession(context);
    return context;
  }

  bool _isCurrent(AuthSessionContext context) =>
      !_disposed && _auth.isSessionContextCurrent(context);

  void _requireCurrent(AuthSessionContext context) {
    if (!_isCurrent(context)) throw const AuthSessionChangedException();
  }

  void _observeSession(AuthSessionContext? context) {
    if (_disposed) return;
    // Delayed events must not revoke a newer, synchronously captured session.
    if (context != null && !_auth.isSessionContextCurrent(context)) return;
    if (context == null &&
        _walletSession != null &&
        _auth.isSessionContextCurrent(_walletSession!)) {
      return;
    }
    if (_walletSession == context) return;
    _clearSessions();
    _walletSession = context;
  }

  void _clearSessions() {
    final sessions = _sessions.values.toList();
    _sessions.clear();
    _walletSession = null;
    for (final session in sessions) {
      // dispose revokes the session and its timer before its first await.
      unawaited(session.dispose());
    }
  }

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
    final context = await _captureSession();
    _requireCurrent(context);
    final response = await _client.rpc.routedSwap.quote(
      from: from.id,
      to: to.id,
      amount: amount.toString(),
      slippage: slippage,
      order: order,
      provider: provider,
    );

    _requireCurrent(context);
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

  /// Asks KDF to calculate and price Max, including native gas funding and
  /// known atomic commitments. The returned amount and minimum are
  /// one snapshot.
  Future<RoutedSwapOffer> quoteMax({
    required AssetId from,
    required AssetId to,
    double? slippage,
    rpc.RoutedSwapOrder? order,
    String? provider,
  }) async {
    final context = await _captureSession();
    _requireCurrent(context);
    final response = await _client.rpc.routedSwap.quoteMax(
      from: from.id,
      to: to.id,
      slippage: slippage,
      order: order,
      provider: provider,
    );
    _requireCurrent(context);
    final route = response.best;
    if (route == null) {
      throw StateError('A successful Max quote must contain a route');
    }
    return _offerFrom(
      route,
      from: from,
      to: to,
      order: order,
      slippage: slippage,
    );
  }

  /// Compatibility wrapper around [quoteMax]. [balance] never resizes KDF's
  /// quote; KDF owns spendable balances and the concrete source amount.
  Future<RoutedSwapMaxSell> maxSellAmount({
    required AssetId from,
    required AssetId to,
    required Decimal balance,
    double? slippage,
    rpc.RoutedSwapOrder? order,
    String? provider,
  }) async {
    final offer = await quoteMax(
      from: from,
      to: to,
      slippage: slippage,
      order: order,
      provider: provider,
    );
    final gas = from.isChildAsset
        ? Decimal.zero
        : offer.networkFees
              .where((fee) => fee.assetId == from || fee.ticker == from.id)
              .fold<Decimal>(
                Decimal.zero,
                (sum, fee) => sum + (fee.requiredBalance ?? fee.amount),
              );
    final providerFees = offer.costs
        .where(
          (cost) =>
              cost.kind == RoutedSwapCostKind.providerFee &&
              !cost.isDeductedFromReceive &&
              cost.assetId == from,
        )
        .fold<Decimal>(Decimal.zero, (sum, cost) => sum + cost.amount);
    return RoutedSwapMaxSell(
      amount: offer.sellAmount,
      reservedForFees: gas + providerFees,
      feeAsset: from.isChildAsset && providerFees == Decimal.zero
          ? from.parentId
          : from,
      reservedForProviderFees: providerFees,
      offer: offer,
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
    final context = await _captureSession();
    _requireCurrent(context);
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

    if (!_isCurrent(context)) {
      throw RoutedSwapStartUnconfirmedException(
        const AuthSessionChangedException(),
        taskId: init.taskId,
      );
    }

    // Resolve the uuid before handing back a handle. Everything after this
    // point is recoverable; the window before it is not, so it is closed here
    // rather than left to each caller.
    Object? lastError;
    for (var attempt = 0; attempt < _firstReadAttempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_firstReadRetryDelay * attempt);
      }
      if (!_isCurrent(context)) {
        throw RoutedSwapStartUnconfirmedException(
          const AuthSessionChangedException(),
          taskId: init.taskId,
        );
      }
      try {
        final first = await _client.rpc.routedSwap.status(init.taskId);
        _requireCurrent(context);
        final seed = _progressFromStatus(first.details, accepted: offer);
        final session = _RoutedSwapSession(
          manager: this,
          walletSession: context,
          uuid: first.details.uuid,
          taskId: init.taskId,
          offer: offer,
          seed: seed,
        );
        return _register(session);
      } on Object catch (error) {
        lastError = error;
        if (!_isCurrent(context)) {
          throw RoutedSwapStartUnconfirmedException(error, taskId: init.taskId);
        }
      }
    }

    // Amounts and minima cannot correlate a history entry to this task.
    // Even one matching record may belong to another concurrent caller.
    throw RoutedSwapStartUnconfirmedException(
      lastError ?? StateError('No status for task ${init.taskId}'),
      taskId: init.taskId,
    );
  }

  /// Re-attaches to a swap by its durable id.
  ///
  /// Returns the live session when one is running in this process, and
  /// otherwise a handle that follows the persisted record — so a screen opened
  /// after a restart behaves the same as one that never closed.
  ///
  /// Throws [RoutedSwapNotFoundException] when nothing is known about [uuid].
  Future<RoutedSwapHandle> watch(String uuid) async {
    final context = await _captureSession();
    _requireCurrent(context);
    final live = _sessions[uuid];
    if (live != null && !live.isDisposed) return _RoutedSwapHandle(live);

    final entry = await _entryFor(uuid, context);
    if (entry == null) throw RoutedSwapNotFoundException(uuid);

    // A swap KDF is still tracking after a restart has no task id any client
    // can hold, so history polling is the only way to follow it.
    final session = _RoutedSwapSession(
      manager: this,
      walletSession: context,
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
    final context = await _captureSession();
    final entries = <RoutedSwapProgress>[];
    for (var page = 1; page <= 20; page++) {
      _requireCurrent(context);
      final result = await history(
        filter: rpc.RoutedSwapHistoryFilter.inFlight,
        limit: pageSize,
        pageNumber: page,
      );
      _requireCurrent(context);
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
    final context = await _captureSession();
    _requireCurrent(context);
    final page = await _client.rpc.routedSwap.history(
      filter: filter,
      myCoin: from?.id,
      otherCoin: to?.id,
      fromTimestamp: createdAfter == null ? null : _unixSeconds(createdAfter),
      toTimestamp: createdBefore == null ? null : _unixSeconds(createdBefore),
      limit: limit,
      pageNumber: pageNumber,
    );
    _requireCurrent(context);
    return RoutedSwapHistoryPage(
      entries: [
        for (final entry in page.entries)
          _progressFromEntry(
            entry,
            accepted: _sessions[entry.uuid]?.offer,
            previous: _sessions[entry.uuid]?.latest,
          ),
      ],
      total: page.total,
      pageNumber: page.pageNumber,
      totalPages: page.totalPages,
    );
  }

  /// Releases every live session.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final sessions = _sessions.values.toList();
    _sessions.clear();
    // Revoke every timer synchronously, before waiting for auth cancellation.
    final pending = [for (final session in sessions) session.dispose()];
    final authCancellation = _authSubscription?.cancel();
    if (authCancellation != null) pending.add(authCancellation);
    await Future.wait(pending);
  }
}
