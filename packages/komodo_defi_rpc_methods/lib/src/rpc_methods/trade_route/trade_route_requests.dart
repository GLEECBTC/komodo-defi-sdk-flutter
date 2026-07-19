import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';

abstract class _TradeRouteRequest<T extends BaseResponse>
    extends BaseRequest<T, GeneralErrorResponse> {
  _TradeRouteRequest({required super.method, super.rpcPass})
    : super(mmrpc: RpcVersion.v2_0);

  RouteJson get requestParams;

  @override
  RouteJson toJson() => {...super.toJson(), 'params': requestParams};
}

final class TradeRouteCapabilitiesRequest
    extends _TradeRouteRequest<TradeRouteCapabilitiesResponse> {
  TradeRouteCapabilitiesRequest({
    this.providerSnapshot,
    List<ExternalProvider> providers = const [ExternalProvider.lifi],
    List<String> tickers = const [],
    super.rpcPass,
  }) : providers = List.unmodifiable(providers),
       tickers = List.unmodifiable(tickers),
       super(method: 'experimental::trade_route::capabilities');

  /// Optional caller-supplied bounded metadata.
  ///
  /// When omitted, KDF performs discovery through its configured transport.
  /// Supplying a snapshot preserves the original request behavior.
  final ProviderMetadataSnapshot? providerSnapshot;
  final List<ExternalProvider> providers;
  final List<String> tickers;

  @override
  RouteJson get requestParams {
    if (providerSnapshot != null && !providerSnapshot!.isExecutable) {
      throw StateError('Provider metadata snapshot is not executable.');
    }
    return {
      'providers': providers.map((provider) => provider.wireName).toList(),
      'tickers': tickers,
      if (providerSnapshot != null)
        'provider_snapshot': providerSnapshot!.toJson(),
    };
  }

  @override
  TradeRouteCapabilitiesResponse parse(RouteJson json) =>
      TradeRouteCapabilitiesResponse.parse(json);
}

final class TradeRouteEvaluateRequest
    extends _TradeRouteRequest<TradeRouteEvaluateResponse> {
  TradeRouteEvaluateRequest({
    required this.intent,
    required List<CandidateSource> candidateSources,
    List<ExternalProviderCandidate> externalCandidates = const [],
    this.valuationSnapshot,
    super.rpcPass,
  }) : candidateSources = List.unmodifiable(candidateSources),
       externalCandidates = List.unmodifiable(externalCandidates),
       super(method: 'experimental::trade_route::evaluate');

  final TradeIntent intent;
  final List<CandidateSource> candidateSources;
  final List<ExternalProviderCandidate> externalCandidates;
  final ValuationSnapshot? valuationSnapshot;

  @override
  RouteJson get requestParams {
    if (valuationSnapshot != null && !valuationSnapshot!.isExecutable) {
      throw StateError('Valuation snapshot is not executable.');
    }
    return {
      'intent': intent.toRequestJson(),
      'candidate_sources': candidateSources
          .map((source) => source.wireName)
          .toList(growable: false),
      'external_candidates': externalCandidates
          .map((candidate) => candidate.toRequestJson())
          .toList(growable: false),
      'valuation_snapshot': valuationSnapshot?.toJson(),
    };
  }

  @override
  TradeRouteEvaluateResponse parse(RouteJson json) =>
      TradeRouteEvaluateResponse.parse(json);
}

final class GetTradeRouteExecutionRequest
    extends _TradeRouteRequest<RouteExecutionDetailsResponse> {
  GetTradeRouteExecutionRequest({required this.routeExecutionId, super.rpcPass})
    : super(method: 'experimental::trade_route::get_execution');

  final String routeExecutionId;
  @override
  RouteJson get requestParams => {'route_execution_id': routeExecutionId};
  @override
  RouteExecutionDetailsResponse parse(RouteJson json) =>
      RouteExecutionDetailsResponse.parse(json);
}

final class ListTradeRouteExecutionsRequest
    extends _TradeRouteRequest<ListRouteExecutionsResponse> {
  ListTradeRouteExecutionsRequest({
    this.state,
    this.cursor,
    this.limit = 50,
    super.rpcPass,
  }) : super(method: 'experimental::trade_route::list_executions') {
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
  }

  final RouteActivityState? state;
  final String? cursor;
  final int limit;

  @override
  RouteJson get requestParams => {
    if (state != null) 'state': state!.wireName,
    if (cursor != null) 'cursor': cursor,
    'limit': limit,
  };

  @override
  ListRouteExecutionsResponse parse(RouteJson json) =>
      ListRouteExecutionsResponse.parse(json);
}

final class TradeRouteQuoteRequest
    extends _TradeRouteRequest<TradeRouteQuoteResponse> {
  TradeRouteQuoteRequest({
    required this.intent,
    required List<RouteSource> routeSources,
    this.valuationSnapshot,
    this.rankingPolicy = RankingPolicy.maximumNetMinimumReceive,
    super.rpcPass,
  }) : routeSources = List.unmodifiable(routeSources),
       super(method: 'experimental::trade_route::quote');

  final TradeIntent intent;
  final List<RouteSource> routeSources;
  final ValuationSnapshot? valuationSnapshot;
  final RankingPolicy rankingPolicy;

  @override
  RouteJson get requestParams {
    if (valuationSnapshot != null && !valuationSnapshot!.isExecutable) {
      throw StateError('Valuation snapshot is not executable.');
    }
    return {
      'intent': intent.toRequestJson(),
      'route_sources': routeSources
          .map((source) => source.wireName)
          .toList(growable: false),
      'valuation_snapshot': valuationSnapshot?.toJson(),
      'ranking_policy': rankingPolicy.wireName,
    };
  }

  @override
  TradeRouteQuoteResponse parse(RouteJson json) =>
      TradeRouteQuoteResponse.parse(json);
}

final class PrepareExecutionRequest
    extends _TradeRouteRequest<PrepareExecutionResponse> {
  PrepareExecutionRequest({
    required this.evaluationId,
    required this.candidateId,
    required this.candidateDigest,
    required this.finalMinimumReceive,
    required this.consentExpiresAt,
    required List<PrepareExecutionStageLimits> stages,
    super.rpcPass,
  }) : stages = List.unmodifiable(stages),
       super(method: 'experimental::trade_route::prepare_execution');

  final String evaluationId;
  final String candidateId;
  final String candidateDigest;
  final String finalMinimumReceive;
  final DateTime consentExpiresAt;
  final List<PrepareExecutionStageLimits> stages;

  @override
  RouteJson get requestParams {
    if (stages.any((stage) => !stage.isExecutable)) {
      throw StateError('Prepare-execution limits are not executable.');
    }
    return {
      'evaluation_id': evaluationId,
      'candidate_id': candidateId,
      'candidate_digest': candidateDigest,
      'final_minimum_receive': finalMinimumReceive,
      'consent_expires_at': consentExpiresAt.toUtc().toIso8601String(),
      'stages': stages
          .map((stage) => stage.toRequestJson())
          .toList(growable: false),
    };
  }

  @override
  PrepareExecutionResponse parse(RouteJson json) =>
      PrepareExecutionResponse.parse(json);
}

final class ExternalExecutionInitRequest
    extends _TradeRouteRequest<NewTaskResponse> {
  ExternalExecutionInitRequest({
    required this.executionId,
    required this.idempotencyKey,
    required this.stageConsent,
    super.rpcPass,
  }) : super(method: 'task::external_execution::init');

  final String executionId;
  final String idempotencyKey;
  final StageConsent stageConsent;
  @override
  RouteJson get requestParams => {
    'execution_id': executionId,
    'idempotency_key': idempotencyKey,
    'stage_consent': stageConsent.toRequestJson(),
  };
  @override
  NewTaskResponse parse(RouteJson json) => NewTaskResponse.parse(json);
}

final class ExternalExecutionStatusRequest
    extends _TradeRouteRequest<ExternalExecutionTaskStatusResponse> {
  ExternalExecutionStatusRequest({
    required this.taskId,
    this.forgetIfFinished = true,
    super.rpcPass,
  }) : super(method: 'task::external_execution::status');

  final int taskId;
  final bool forgetIfFinished;
  @override
  RouteJson get requestParams => {
    'task_id': taskId,
    'forget_if_finished': forgetIfFinished,
  };
  @override
  bool get parseTaskErrorStatusAsResponse => true;
  @override
  ExternalExecutionTaskStatusResponse parse(RouteJson json) =>
      ExternalExecutionTaskStatusResponse.parse(json);
}

final class ExternalExecutionUserActionRequest
    extends _TradeRouteRequest<RouteActionResponse> {
  ExternalExecutionUserActionRequest({
    required this.taskId,
    required this.userAction,
    super.rpcPass,
  }) : super(method: 'task::external_execution::user_action');

  final int taskId;
  final ExternalExecutionUserAction userAction;
  @override
  RouteJson get requestParams => {
    'task_id': taskId,
    'user_action': userAction.toJson(),
  };
  @override
  RouteActionResponse parse(RouteJson json) => RouteActionResponse.parse(json);
}

final class CancelExternalExecutionRequest
    extends _TradeRouteRequest<RouteCancelResponse> {
  CancelExternalExecutionRequest({required this.executionId, super.rpcPass})
    : super(method: 'task::external_execution::cancel');
  final String executionId;
  @override
  RouteJson get requestParams => {'execution_id': executionId};
  @override
  RouteCancelResponse parse(RouteJson json) => RouteCancelResponse.parse(json);
}

final class ChainTxReceiptRequest
    extends _TradeRouteRequest<ChainTxReceiptResponse> {
  ChainTxReceiptRequest({
    required this.coin,
    required this.txHash,
    this.requiredConfirmations,
    super.rpcPass,
  }) : super(method: 'experimental::chain_tx::receipt');
  final String coin;
  final String txHash;
  final int? requiredConfirmations;
  @override
  RouteJson get requestParams => {
    'coin': coin,
    'tx_hash': txHash,
    if (requiredConfirmations != null)
      'required_confirmations': requiredConfirmations,
  };
  @override
  ChainTxReceiptResponse parse(RouteJson json) =>
      ChainTxReceiptResponse.parse(json);
}

final class TradeRouteInitRequest extends _TradeRouteRequest<NewTaskResponse> {
  TradeRouteInitRequest({
    required this.routeExecutionId,
    required this.idempotencyKey,
    required this.routeConsent,
    super.rpcPass,
  }) : super(method: 'task::trade_route::init');
  final String routeExecutionId;
  final String idempotencyKey;
  final TradeRouteInitConsent routeConsent;
  @override
  RouteJson get requestParams => {
    'route_execution_id': routeExecutionId,
    'idempotency_key': idempotencyKey,
    'route_consent': routeConsent.toRequestJson(),
  };
  @override
  NewTaskResponse parse(RouteJson json) => NewTaskResponse.parse(json);
}

final class TradeRouteStatusRequest
    extends _TradeRouteRequest<TradeRouteTaskStatusResponse> {
  TradeRouteStatusRequest({
    required this.taskId,
    this.forgetIfFinished = true,
    super.rpcPass,
  }) : super(method: 'task::trade_route::status');
  final int taskId;
  final bool forgetIfFinished;
  @override
  RouteJson get requestParams => {
    'task_id': taskId,
    'forget_if_finished': forgetIfFinished,
  };
  @override
  bool get parseTaskErrorStatusAsResponse => true;
  @override
  TradeRouteTaskStatusResponse parse(RouteJson json) =>
      TradeRouteTaskStatusResponse.parse(json);
}

final class TradeRouteUserActionRequest
    extends _TradeRouteRequest<RouteActionResponse> {
  TradeRouteUserActionRequest({
    required this.taskId,
    required this.userAction,
    super.rpcPass,
  }) : super(method: 'task::trade_route::user_action');
  final int taskId;
  final RouteExecutionUserAction userAction;
  @override
  RouteJson get requestParams => {
    'task_id': taskId,
    'user_action': userAction.toJson(),
  };
  @override
  RouteActionResponse parse(RouteJson json) => RouteActionResponse.parse(json);
}

final class CancelTradeRouteRequest
    extends _TradeRouteRequest<RouteCancelResponse> {
  CancelTradeRouteRequest({required this.routeExecutionId, super.rpcPass})
    : super(method: 'task::trade_route::cancel');
  final String routeExecutionId;
  @override
  RouteJson get requestParams => {'route_execution_id': routeExecutionId};
  @override
  RouteCancelResponse parse(RouteJson json) => RouteCancelResponse.parse(json);
}
