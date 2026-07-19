import 'dart:async';

import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// The RPC boundary used by [TradeRouteManager].
///
/// The public boundary keeps lifecycle and authorization behavior independently
/// testable while the default implementation delegates to KDF's typed route
/// namespace.
abstract interface class TradeRouteRpcGateway {
  /// Reads a route by its durable execution ID.
  Future<RouteExecutionDetailsResponse> getExecution({
    required String routeExecutionId,
  });

  /// Reads one authoritative Activity page.
  Future<ListRouteExecutionsResponse> listExecutions({
    required int limit,
    RouteActivityState? state,
    String? cursor,
  });

  /// Initializes or reattaches a durable route task.
  Future<NewTaskResponse> initTradeRoute({
    required String routeExecutionId,
    required String idempotencyKey,
    required TradeRouteInitConsent routeConsent,
  });

  /// Reads one ephemeral task status.
  Future<TradeRouteTaskStatusResponse> tradeRouteStatus({
    required int taskId,
    required bool forgetIfFinished,
  });

  /// Delivers one typed user action to the ephemeral task.
  Future<RouteActionResponse> tradeRouteUserAction({
    required int taskId,
    required RouteExecutionUserAction userAction,
  });

  /// Applies KDF's durable route cancellation operation.
  Future<RouteCancelResponse> cancelTradeRoute({
    required String routeExecutionId,
  });
}

/// Optional typed discovery/quote boundary used by [TradeRouteManager].
///
/// It is separate from [TradeRouteRpcGateway] so lifecycle-only embedders and
/// test doubles are not forced to implement quote plumbing. The manager never
/// exposes the advisory `evaluate` RPC as executable work; product quotes use
/// KDF's Case-A `quote` contract exclusively.
abstract interface class TradeRouteDiscoveryRpcGateway {
  /// Reads KDF's executable route capability projection.
  Future<TradeRouteCapabilitiesResponse> capabilities({
    required List<ExternalProvider> providers,
    required List<String> tickers,
    ProviderMetadataSnapshot? providerSnapshot,
  });

  /// Creates executable Case-A route candidates.
  Future<TradeRouteQuoteResponse> quote({
    required TradeIntent intent,
    required List<RouteSource> routeSources,
    required RankingPolicy rankingPolicy,
    ValuationSnapshot? valuationSnapshot,
  });

  /// Revalidates one quoted candidate and returns digest-bound Review consent.
  Future<PrepareExecutionResponse> prepareExecution({
    required String evaluationId,
    required String candidateId,
    required String candidateDigest,
    required String finalMinimumReceive,
    required DateTime consentExpiresAt,
    required List<PrepareExecutionStageLimits> stages,
  });
}

/// A local handle joining KDF's durable route identity to its current task.
///
/// [routeExecutionId] remains authoritative across restarts. [taskId] is only
/// an ephemeral polling/delivery handle and must be refreshed with
/// [TradeRouteManager.reattachTradeRoute] when it is no longer valid.
final class TradeRouteTaskHandle {
  /// Creates a handle from a durable route ID and ephemeral task ID.
  const TradeRouteTaskHandle({
    required this.routeExecutionId,
    required this.taskId,
  });

  /// The authoritative ID of the durable route journal.
  final String routeExecutionId;

  /// The current process-local task ID used for polling and action delivery.
  final int taskId;
}

/// The durable snapshot read before a new ephemeral task was attached.
final class ReattachedTradeRoute {
  /// Creates a reattachment result.
  const ReattachedTradeRoute({required this.execution, required this.task});

  /// The durable snapshot read before task initialization.
  final RouteExecutionDetails execution;

  /// The newly returned ephemeral task handle.
  final TradeRouteTaskHandle task;
}

/// Acknowledges delivery of a user action to the current route task.
///
/// Even when [result] is `success`, this says nothing about trade completion.
/// Callers must continue observing the route's durable status.
final class TradeRouteActionAcknowledgement {
  /// Creates an action-delivery acknowledgement.
  const TradeRouteActionAcknowledgement({
    required this.routeExecutionId,
    required this.taskId,
    required this.result,
  });

  /// The authoritative durable route ID.
  final String routeExecutionId;

  /// The ephemeral task that accepted the action delivery.
  final int taskId;

  /// KDF's delivery result string.
  final String result;

  /// Whether KDF acknowledged action delivery, not whether the route finished.
  bool get wasDelivered => result == 'success';
}

/// Base class for local manager policy failures.
sealed class TradeRouteManagerException implements Exception {
  /// Creates a local policy exception with a sanitized [message].
  const TradeRouteManagerException(this.message);

  /// A sanitized description suitable for local diagnostics.
  final String message;

  @override
  String toString() => message;
}

/// KDF did not explicitly authorize the requested durable route control.
final class TradeRouteControlNotAuthorizedException
    extends TradeRouteManagerException {
  /// Creates a denied-control exception.
  const TradeRouteControlNotAuthorizedException({
    required this.routeExecutionId,
    required this.control,
  }) : super(
         'Route $routeExecutionId does not authorize the $control control.',
       );

  /// The durable route ID that rejected the control.
  final String routeExecutionId;

  /// The known control requested by the caller.
  final String control;
}

/// A user action was absent, stale, unknown, or not explicitly allowed.
final class TradeRouteActionNotAuthorizedException
    extends TradeRouteManagerException {
  /// Creates a denied-action exception.
  const TradeRouteActionNotAuthorizedException({
    required this.routeExecutionId,
    required String reason,
  }) : super('Route $routeExecutionId rejected the local action: $reason');

  /// The durable route ID that rejected the action.
  final String routeExecutionId;
}

/// A task response referred to a route other than the durable route requested.
final class TradeRouteIdentityMismatchException
    extends TradeRouteManagerException {
  /// Creates an identity mismatch exception.
  const TradeRouteIdentityMismatchException({
    required this.expectedRouteExecutionId,
    required this.actualRouteExecutionId,
  }) : super(
         'Expected route $expectedRouteExecutionId, got '
         '$actualRouteExecutionId.',
       );

  /// The durable route ID requested by the caller.
  final String expectedRouteExecutionId;

  /// The conflicting route ID returned by KDF.
  final String actualRouteExecutionId;
}

/// High-level lifecycle and control helpers for durable unified-swap routes.
///
/// The manager deliberately does not rank, regroup, or otherwise apply UI
/// policy to route candidates or Activity results.
class TradeRouteManager {
  /// Creates a manager backed by the SDK's shared API [client].
  TradeRouteManager({
    required ApiClient client,
    Duration defaultPollingInterval = const Duration(seconds: 2),
  }) : this.withGateway(
         gateway: _ApiClientTradeRouteRpcGateway(client),
         defaultPollingInterval: defaultPollingInterval,
       );

  /// Creates a manager around an alternate typed RPC gateway.
  ///
  /// This is primarily useful for deterministic lifecycle tests.
  TradeRouteManager.withGateway({
    required TradeRouteRpcGateway gateway,
    this.defaultPollingInterval = const Duration(seconds: 2),
  }) : _gateway = gateway {
    _validatePollingInterval(defaultPollingInterval);
  }

  final TradeRouteRpcGateway _gateway;

  /// The interval used by [observeStatus] when none is provided per stream.
  final Duration defaultPollingInterval;
  final Set<_TradeRouteObservation> _observations = {};
  bool _isDisposed = false;

  /// Returns the one deterministic idempotency key for a durable route.
  static String idempotencyKeyFor(String routeExecutionId) {
    if (routeExecutionId.trim().isEmpty) {
      throw ArgumentError.value(
        routeExecutionId,
        'routeExecutionId',
        'must not be empty',
      );
    }
    return 'trade-route:$routeExecutionId';
  }

  /// Reads KDF's executable capability projection.
  Future<TradeRouteCapabilitiesResult> capabilities({
    ProviderMetadataSnapshot? providerSnapshot,
    List<ExternalProvider> providers = const [ExternalProvider.lifi],
    List<String> tickers = const [],
  }) async {
    _ensureNotDisposed();
    final gateway = _discoveryGateway();
    final response = await gateway.capabilities(
      providerSnapshot: providerSnapshot,
      providers: providers,
      tickers: tickers,
    );
    return response.result;
  }

  /// Creates executable Case-A route candidates from KDF-owned discovery.
  ///
  /// Advisory `evaluate` output is intentionally not surfaced here.
  Future<TradeRouteQuoteResult> quote({
    required TradeIntent intent,
    required List<RouteSource> routeSources,
    ValuationSnapshot? valuationSnapshot,
    RankingPolicy rankingPolicy = RankingPolicy.maximumNetMinimumReceive,
  }) async {
    _ensureNotDisposed();
    final gateway = _discoveryGateway();
    final response = await gateway.quote(
      intent: intent,
      routeSources: routeSources,
      valuationSnapshot: valuationSnapshot,
      rankingPolicy: rankingPolicy,
    );
    return response.result;
  }

  /// Revalidates a selected candidate at the Review boundary.
  ///
  /// Unknown stage or approval variants, missing preparation bindings, and
  /// mismatched Review/consent identities fail closed before callers can pass
  /// the returned consent to route initialization.
  Future<PrepareExecutionResult> prepareExecution({
    required String evaluationId,
    required String candidateId,
    required String candidateDigest,
    required String finalMinimumReceive,
    required DateTime consentExpiresAt,
    required List<PrepareExecutionStageLimits> stages,
  }) async {
    _ensureNotDisposed();
    final gateway = _discoveryGateway();
    final response = await gateway.prepareExecution(
      evaluationId: evaluationId,
      candidateId: candidateId,
      candidateDigest: candidateDigest,
      finalMinimumReceive: finalMinimumReceive,
      consentExpiresAt: consentExpiresAt,
      stages: stages,
    );
    if (!response.result.isExecutable ||
        !_hasValidPreparationDigests(response.result)) {
      throw StateError('Prepared trade route is not executable.');
    }
    return response.result;
  }

  /// Initializes a durable route and returns its current ephemeral task.
  Future<TradeRouteTaskHandle> initTradeRoute({
    required String routeExecutionId,
    required RouteConsent routeConsent,
  }) async {
    _ensureNotDisposed();
    final response = await _gateway.initTradeRoute(
      routeExecutionId: routeExecutionId,
      idempotencyKey: idempotencyKeyFor(routeExecutionId),
      routeConsent: routeConsent,
    );
    return TradeRouteTaskHandle(
      routeExecutionId: routeExecutionId,
      taskId: response.taskId,
    );
  }

  /// Reads the authoritative durable route projection.
  Future<RouteExecutionDetails> getExecution({
    required String routeExecutionId,
  }) async {
    _ensureNotDisposed();
    final response = await _gateway.getExecution(
      routeExecutionId: routeExecutionId,
    );
    _validateRouteIdentity(routeExecutionId, response.result.routeExecutionId);
    return response.result;
  }

  /// Reattaches to a durable route after first proving the journal exists.
  ///
  /// The durable `get_execution` read is always performed before `init`. The
  /// exact persisted Activity consent is then sent back to KDF as an attachment
  /// proof, so restart does not depend on wallet-local full consent material.
  Future<ReattachedTradeRoute> reattachTradeRoute({
    required String routeExecutionId,
  }) async {
    final execution = await getExecution(routeExecutionId: routeExecutionId);
    _ensureNotDisposed();
    final response = await _gateway.initTradeRoute(
      routeExecutionId: routeExecutionId,
      idempotencyKey: idempotencyKeyFor(routeExecutionId),
      routeConsent: execution.routeConsent,
    );
    final task = TradeRouteTaskHandle(
      routeExecutionId: routeExecutionId,
      taskId: response.taskId,
    );
    return ReattachedTradeRoute(execution: execution, task: task);
  }

  /// Polls the current ephemeral task without forgetting a finished task.
  Future<TradeRouteTaskStatusResponse> pollStatus(
    TradeRouteTaskHandle task,
  ) async {
    _ensureNotDisposed();
    final response = await _gateway.tradeRouteStatus(
      taskId: task.taskId,
      forgetIfFinished: false,
    );
    _validateStatusIdentity(task.routeExecutionId, response.result);
    return response;
  }

  /// Observes a route task by local polling.
  ///
  /// Cancelling the returned subscription only stops this polling loop. It
  /// never invokes KDF's durable cancel RPC. Terminal and unknown task status
  /// variants are emitted once and then stop the local loop.
  Stream<TradeRouteTaskStatusResponse> observeStatus(
    TradeRouteTaskHandle task, {
    Duration? pollingInterval,
  }) {
    _ensureNotDisposed();
    final interval = pollingInterval ?? defaultPollingInterval;
    _validatePollingInterval(interval);

    late final _TradeRouteObservation observation;
    observation = _TradeRouteObservation(
      pollingInterval: interval,
      poll: () => _gateway.tradeRouteStatus(
        taskId: task.taskId,
        forgetIfFinished: false,
      ),
      validate: (response) {
        _validateStatusIdentity(task.routeExecutionId, response.result);
      },
      onFinished: () => _observations.remove(observation),
    );
    _observations.add(observation);
    return observation.stream;
  }

  /// Explicitly cancels a reversible route.
  ///
  /// A fresh durable snapshot must explicitly set `can_cancel`; all other
  /// control combinations fail closed without invoking the backend cancel RPC.
  Future<RouteCancelResponse> cancelTradeRoute({
    required String routeExecutionId,
  }) async {
    final execution = await getExecution(routeExecutionId: routeExecutionId);
    if (!_hasKnownExecutionState(execution.status) ||
        !execution.status.controls.canCancel ||
        execution.status.controls.reconciliationOnly) {
      throw TradeRouteControlNotAuthorizedException(
        routeExecutionId: routeExecutionId,
        control: 'cancel',
      );
    }
    _ensureNotDisposed();
    return _gateway.cancelTradeRoute(routeExecutionId: routeExecutionId);
  }

  /// Explicitly asks KDF to stop scheduling work after the current stage.
  ///
  /// This uses `task::trade_route::cancel`, whose durable outcome becomes
  /// `stop_after_current` when irreversible work exists, only when the latest
  /// server controls explicitly advertise `can_stop_after_current`.
  Future<RouteCancelResponse> stopAfterCurrent({
    required String routeExecutionId,
  }) async {
    final execution = await getExecution(routeExecutionId: routeExecutionId);
    if (!_hasKnownExecutionState(execution.status) ||
        !execution.status.controls.canStopAfterCurrent ||
        execution.status.controls.reconciliationOnly) {
      throw TradeRouteControlNotAuthorizedException(
        routeExecutionId: routeExecutionId,
        control: 'stop_after_current',
      );
    }
    _ensureNotDisposed();
    return _gateway.cancelTradeRoute(routeExecutionId: routeExecutionId);
  }

  /// Delivers a server-authorized action to the current ephemeral task.
  ///
  /// The latest durable pending action, action ID, state revision, allowed
  /// action values, replacement authority, and (for stop-after-current)
  /// controls must all agree. An unknown action discriminator or allowed-action
  /// value can never execute.
  Future<TradeRouteActionAcknowledgement> deliverUserAction({
    required TradeRouteTaskHandle task,
    required RouteExecutionUserAction userAction,
  }) async {
    final execution = await getExecution(
      routeExecutionId: task.routeExecutionId,
    );
    final pending = execution.status.pendingUserAction;
    final actionType = userAction.actionType;
    const knownActionTypes = {
      'accept_replacement',
      'reject_change',
      'select_recovery_route',
      'stop_after_current',
    };
    if (!knownActionTypes.contains(actionType)) {
      throw TradeRouteActionNotAuthorizedException(
        routeExecutionId: task.routeExecutionId,
        reason: 'unknown action type $actionType',
      );
    }
    if (pending == null) {
      throw TradeRouteActionNotAuthorizedException(
        routeExecutionId: task.routeExecutionId,
        reason: 'there is no pending server action',
      );
    }
    if (!_hasKnownExecutionState(execution.status) ||
        !pending.reason.isExecutable) {
      throw TradeRouteActionNotAuthorizedException(
        routeExecutionId: task.routeExecutionId,
        reason: 'the pending action has an unknown server discriminator',
      );
    }

    if (userAction.actionId != pending.actionId ||
        userAction.expectedStateRevision != execution.status.stateRevision) {
      throw TradeRouteActionNotAuthorizedException(
        routeExecutionId: task.routeExecutionId,
        reason: 'the action ID or state revision is stale',
      );
    }
    final isAllowed = pending.allowedActions.any(
      (allowed) =>
          allowed.isExecutable && allowed.rawValue == userAction.actionType,
    );
    if (!isAllowed) {
      throw TradeRouteActionNotAuthorizedException(
        routeExecutionId: task.routeExecutionId,
        reason: '$actionType is not explicitly allowed',
      );
    }
    if (userAction is RouteAcceptReplacementAction) {
      _validateReplacementAcceptance(
        routeExecutionId: task.routeExecutionId,
        pending: pending,
        action: userAction,
      );
    }
    if (actionType == 'stop_after_current' &&
        (!execution.status.controls.canStopAfterCurrent ||
            execution.status.controls.reconciliationOnly)) {
      throw TradeRouteControlNotAuthorizedException(
        routeExecutionId: task.routeExecutionId,
        control: 'stop_after_current',
      );
    }

    _ensureNotDisposed();
    final response = await _gateway.tradeRouteUserAction(
      taskId: task.taskId,
      userAction: userAction,
    );
    return TradeRouteActionAcknowledgement(
      routeExecutionId: task.routeExecutionId,
      taskId: task.taskId,
      result: response.result,
    );
  }

  /// Reads one authoritative Activity page without reordering its executions.
  Future<ListRouteExecutionsResult> listExecutions({
    RouteActivityState? state,
    String? cursor,
    int limit = 50,
  }) async {
    _ensureNotDisposed();
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    final response = await _gateway.listExecutions(
      state: state,
      cursor: cursor,
      limit: limit,
    );
    return response.result;
  }

  /// Streams Activity pages in authoritative backend order.
  ///
  /// Empty pages are not terminal when KDF supplies a next cursor. Repeated
  /// cursor values are rejected to prevent an unbounded client loop.
  Stream<ListRouteExecutionsResult> listExecutionPages({
    RouteActivityState? state,
    int limit = 50,
  }) async* {
    String? cursor;
    final followedCursors = <String>{};
    do {
      final page = await listExecutions(
        state: state,
        cursor: cursor,
        limit: limit,
      );
      yield page;

      final nextCursor = page.nextCursor;
      if (nextCursor != null && !followedCursors.add(nextCursor)) {
        throw StateError('KDF repeated an Activity cursor.');
      }
      cursor = nextCursor;
    } while (cursor != null);
  }

  /// Collects every Activity summary without reordering or ranking it.
  Future<List<RouteExecutionSummary>> listAllExecutions({
    RouteActivityState? state,
    int limit = 50,
  }) async {
    final executions = <RouteExecutionSummary>[];
    await for (final page in listExecutionPages(state: state, limit: limit)) {
      executions.addAll(page.executions);
    }
    return List.unmodifiable(executions);
  }

  /// Stops all local polling without changing any durable route.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    final observations = _observations.toList(growable: false);
    _observations.clear();
    for (final observation in observations) {
      observation.stop();
    }
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('TradeRouteManager has been disposed');
    }
  }

  TradeRouteDiscoveryRpcGateway _discoveryGateway() {
    final gateway = _gateway;
    if (gateway is! TradeRouteDiscoveryRpcGateway) {
      throw StateError('Trade route discovery is unavailable');
    }
    return gateway as TradeRouteDiscoveryRpcGateway;
  }

  static void _validatePollingInterval(Duration value) {
    if (value.inMicroseconds <= 0) {
      throw ArgumentError.value(
        value,
        'pollingInterval',
        'must be greater than zero',
      );
    }
  }

  static void _validateRouteIdentity(String expected, String actual) {
    if (actual != expected) {
      throw TradeRouteIdentityMismatchException(
        expectedRouteExecutionId: expected,
        actualRouteExecutionId: actual,
      );
    }
  }

  static void _validateStatusIdentity(
    String expected,
    TradeRouteTaskStatus status,
  ) {
    final details = switch (status) {
      TradeRouteInProgressStatus(:final details) => details,
      TradeRouteUserActionRequiredStatus(:final details) => details,
      TradeRouteOkStatus(:final details) => details,
      TradeRouteErrorStatus() || UnknownTradeRouteTaskStatus() => null,
    };
    if (details != null) {
      _validateRouteIdentity(expected, details.routeExecutionId);
    }
  }

  static bool _hasKnownExecutionState(RouteExecutionStatus status) =>
      status.isExecutable;

  static void _validateReplacementAcceptance({
    required String routeExecutionId,
    required PendingUserAction pending,
    required RouteAcceptReplacementAction action,
  }) {
    Never reject(String reason) => throw TradeRouteActionNotAuthorizedException(
      routeExecutionId: routeExecutionId,
      reason: reason,
    );

    final summary = pending.replacementSummary;
    final authoritativeConsent = summary?.replacementStageConsent;
    if (summary == null || authoritativeConsent == null) {
      reject('a fresh replacement proposal is missing');
    }
    if (summary.proposalDigest.trim().isEmpty ||
        action.proposalDigest.trim().isEmpty) {
      reject('the replacement proposal digest is missing');
    }
    if (!summary.isExecutable ||
        !authoritativeConsent.isExecutable ||
        !action.replacementStageConsent.isExecutable) {
      reject('the replacement proposal is not executable');
    }

    final now = DateTime.now().toUtc();
    final submittedConsent = action.replacementStageConsent;
    if (!summary.expiresAt.isAfter(now) ||
        _replacementConsentExpired(authoritativeConsent, now) ||
        _replacementConsentExpired(submittedConsent, now)) {
      reject('the replacement proposal has expired');
    }
    if (action.proposalDigest != summary.proposalDigest) {
      reject('the replacement proposal digest does not match');
    }

    try {
      final authoritativeDigest = tradeRouteStageConsentDigest(
        authoritativeConsent,
      );
      final submittedDigest = tradeRouteStageConsentDigest(submittedConsent);
      if (authoritativeDigest != authoritativeConsent.consentDigest ||
          submittedDigest != submittedConsent.consentDigest) {
        reject('the replacement stage consent digest is invalid');
      }
      if (tradeRouteCanonicalDigest(authoritativeConsent.toJson()) !=
          tradeRouteCanonicalDigest(submittedConsent.toJson())) {
        reject('the replacement stage consent does not match');
      }
    } on TradeRouteDigestException {
      reject('the replacement stage consent is not canonical');
    }
  }

  static bool _replacementConsentExpired(StageConsent consent, DateTime now) =>
      !consent.stageIntent.consentExpiresAt.isAfter(now) ||
      !consent.routeIntent.consentExpiresAt.isAfter(now) ||
      (consent.atomicOrderGuard?.expiresAt.isAfter(now) == false);

  static bool _hasValidPreparationDigests(PrepareExecutionResult result) {
    final preparedReviewDigest = result.routeConsent.preparedReviewDigest;
    if (preparedReviewDigest == null) return false;
    try {
      if (tradeRoutePreparedExecutionReviewDigest(result.review) !=
          preparedReviewDigest) {
        return false;
      }
      for (final consent in result.routeConsent.externalStageConsents) {
        if (tradeRouteStageConsentDigest(consent) != consent.consentDigest) {
          return false;
        }
      }
      return tradeRouteConsentDigest(result.routeConsent) ==
          result.routeConsent.routeConsentDigest;
    } on TradeRouteDigestException {
      return false;
    }
  }
}

final class _ApiClientTradeRouteRpcGateway
    implements TradeRouteRpcGateway, TradeRouteDiscoveryRpcGateway {
  const _ApiClientTradeRouteRpcGateway(this._client);

  final ApiClient _client;

  @override
  Future<TradeRouteCapabilitiesResponse> capabilities({
    required List<ExternalProvider> providers,
    required List<String> tickers,
    ProviderMetadataSnapshot? providerSnapshot,
  }) => _client.rpc.tradeRoute.capabilities(
    providerSnapshot: providerSnapshot,
    providers: providers,
    tickers: tickers,
  );

  @override
  Future<RouteCancelResponse> cancelTradeRoute({
    required String routeExecutionId,
  }) => _client.rpc.tradeRoute.cancelTradeRoute(
    routeExecutionId: routeExecutionId,
  );

  @override
  Future<RouteExecutionDetailsResponse> getExecution({
    required String routeExecutionId,
  }) => _client.rpc.tradeRoute.getExecution(routeExecutionId: routeExecutionId);

  @override
  Future<NewTaskResponse> initTradeRoute({
    required String routeExecutionId,
    required String idempotencyKey,
    required TradeRouteInitConsent routeConsent,
  }) => _client.rpc.tradeRoute.initTradeRoute(
    routeExecutionId: routeExecutionId,
    idempotencyKey: idempotencyKey,
    routeConsent: routeConsent,
  );

  @override
  Future<ListRouteExecutionsResponse> listExecutions({
    required int limit,
    RouteActivityState? state,
    String? cursor,
  }) => _client.rpc.tradeRoute.listExecutions(
    state: state,
    cursor: cursor,
    limit: limit,
  );

  @override
  Future<TradeRouteQuoteResponse> quote({
    required TradeIntent intent,
    required List<RouteSource> routeSources,
    required RankingPolicy rankingPolicy,
    ValuationSnapshot? valuationSnapshot,
  }) => _client.rpc.tradeRoute.quote(
    intent: intent,
    routeSources: routeSources,
    valuationSnapshot: valuationSnapshot,
    rankingPolicy: rankingPolicy,
  );

  @override
  Future<PrepareExecutionResponse> prepareExecution({
    required String evaluationId,
    required String candidateId,
    required String candidateDigest,
    required String finalMinimumReceive,
    required DateTime consentExpiresAt,
    required List<PrepareExecutionStageLimits> stages,
  }) => _client.rpc.tradeRoute.prepareExecution(
    evaluationId: evaluationId,
    candidateId: candidateId,
    candidateDigest: candidateDigest,
    finalMinimumReceive: finalMinimumReceive,
    consentExpiresAt: consentExpiresAt,
    stages: stages,
  );

  @override
  Future<TradeRouteTaskStatusResponse> tradeRouteStatus({
    required int taskId,
    required bool forgetIfFinished,
  }) => _client.rpc.tradeRoute.tradeRouteStatus(
    taskId: taskId,
    forgetIfFinished: forgetIfFinished,
  );

  @override
  Future<RouteActionResponse> tradeRouteUserAction({
    required int taskId,
    required RouteExecutionUserAction userAction,
  }) => _client.rpc.tradeRoute.tradeRouteUserAction(
    taskId: taskId,
    userAction: userAction,
  );
}

final class _TradeRouteObservation {
  _TradeRouteObservation({
    required this.pollingInterval,
    required this.poll,
    required this.validate,
    required this.onFinished,
  }) {
    _controller = StreamController<TradeRouteTaskStatusResponse>(
      onListen: _start,
      onCancel: stop,
    );
  }

  final Duration pollingInterval;
  final Future<TradeRouteTaskStatusResponse> Function() poll;
  final void Function(TradeRouteTaskStatusResponse) validate;
  final void Function() onFinished;
  final Completer<void> _stopSignal = Completer<void>();
  late final StreamController<TradeRouteTaskStatusResponse> _controller;
  Timer? _timer;
  bool _started = false;
  bool _stopped = false;
  bool _finished = false;

  Stream<TradeRouteTaskStatusResponse> get stream => _controller.stream;

  void _start() {
    if (_started || _stopped) return;
    _started = true;
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      while (!_stopped) {
        final response = await poll();
        if (_stopped) return;
        validate(response);
        _controller.add(response);
        if (_stopsLocalPolling(response.result)) return;
        await _waitForNextPoll();
      }
    } on Object catch (error, stackTrace) {
      if (!_stopped && !_controller.isClosed) {
        _controller.addError(error, stackTrace);
      }
    } finally {
      _finish();
    }
  }

  Future<void> _waitForNextPoll() async {
    final elapsed = Completer<void>();
    _timer = Timer(pollingInterval, elapsed.complete);
    await Future.any([elapsed.future, _stopSignal.future]);
    _timer?.cancel();
    _timer = null;
  }

  bool _stopsLocalPolling(TradeRouteTaskStatus status) =>
      status is TradeRouteOkStatus ||
      status is TradeRouteErrorStatus ||
      status is UnknownTradeRouteTaskStatus;

  void stop() {
    if (_stopped) return;
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    if (!_stopSignal.isCompleted) _stopSignal.complete();
    _finish();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    if (!_controller.isClosed) unawaited(_controller.close());
    onFinished();
  }
}
