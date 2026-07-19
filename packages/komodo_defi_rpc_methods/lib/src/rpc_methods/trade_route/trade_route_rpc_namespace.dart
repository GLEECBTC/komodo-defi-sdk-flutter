import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';

final class TradeRouteMethodsNamespace extends BaseRpcMethodNamespace {
  TradeRouteMethodsNamespace(super.client);

  Future<TradeRouteCapabilitiesResponse> capabilities({
    ProviderMetadataSnapshot? providerSnapshot,
    List<ExternalProvider> providers = const [ExternalProvider.lifi],
    List<String> tickers = const [],
    String? rpcPass,
  }) => execute(
    TradeRouteCapabilitiesRequest(
      providerSnapshot: providerSnapshot,
      providers: providers,
      tickers: tickers,
      rpcPass: rpcPass ?? this.rpcPass,
    ),
  );

  Future<TradeRouteEvaluateResponse> evaluate({
    required TradeIntent intent,
    required List<CandidateSource> candidateSources,
    List<ExternalProviderCandidate> externalCandidates = const [],
    ValuationSnapshot? valuationSnapshot,
    String? rpcPass,
  }) => execute(
    TradeRouteEvaluateRequest(
      intent: intent,
      candidateSources: candidateSources,
      externalCandidates: externalCandidates,
      valuationSnapshot: valuationSnapshot,
      rpcPass: rpcPass ?? this.rpcPass,
    ),
  );

  Future<RouteExecutionDetailsResponse> getExecution({
    required String routeExecutionId,
    String? rpcPass,
  }) => execute(
    GetTradeRouteExecutionRequest(
      routeExecutionId: routeExecutionId,
      rpcPass: rpcPass ?? this.rpcPass,
    ),
  );

  Future<ListRouteExecutionsResponse> listExecutions({
    RouteActivityState? state,
    String? cursor,
    int limit = 50,
    String? rpcPass,
  }) => execute(
    ListTradeRouteExecutionsRequest(
      state: state,
      cursor: cursor,
      limit: limit,
      rpcPass: rpcPass ?? this.rpcPass,
    ),
  );

  Future<TradeRouteQuoteResponse> quote({
    required TradeIntent intent,
    required List<RouteSource> routeSources,
    ValuationSnapshot? valuationSnapshot,
    RankingPolicy rankingPolicy = RankingPolicy.maximumNetMinimumReceive,
    String? rpcPass,
  }) => execute(
    TradeRouteQuoteRequest(
      intent: intent,
      routeSources: routeSources,
      valuationSnapshot: valuationSnapshot,
      rankingPolicy: rankingPolicy,
      rpcPass: rpcPass ?? this.rpcPass,
    ),
  );

  Future<PrepareExecutionResponse> prepareExecution({
    required String evaluationId,
    required String candidateId,
    required String candidateDigest,
    required String finalMinimumReceive,
    required DateTime consentExpiresAt,
    required List<PrepareExecutionStageLimits> stages,
    String? rpcPass,
  }) => execute(
    PrepareExecutionRequest(
      evaluationId: evaluationId,
      candidateId: candidateId,
      candidateDigest: candidateDigest,
      finalMinimumReceive: finalMinimumReceive,
      consentExpiresAt: consentExpiresAt,
      stages: stages,
      rpcPass: rpcPass ?? this.rpcPass,
    ),
  );

  Future<NewTaskResponse> initExternalExecution({
    required String executionId,
    required String idempotencyKey,
    required StageConsent stageConsent,
    String? rpcPass,
  }) => execute(
    ExternalExecutionInitRequest(
      executionId: executionId,
      idempotencyKey: idempotencyKey,
      stageConsent: stageConsent,
      rpcPass: rpcPass ?? this.rpcPass,
    ),
  );

  Future<ExternalExecutionTaskStatusResponse> externalExecutionStatus({
    required int taskId,
    bool forgetIfFinished = true,
    String? rpcPass,
  }) => execute(
    ExternalExecutionStatusRequest(
      taskId: taskId,
      forgetIfFinished: forgetIfFinished,
      rpcPass: rpcPass ?? this.rpcPass,
    ),
  );

  Future<RouteActionResponse> externalExecutionUserAction({
    required int taskId,
    required ExternalExecutionUserAction userAction,
    String? rpcPass,
  }) => execute(
    ExternalExecutionUserActionRequest(
      taskId: taskId,
      userAction: userAction,
      rpcPass: rpcPass ?? this.rpcPass,
    ),
  );

  Future<RouteCancelResponse> cancelExternalExecution({
    required String executionId,
    String? rpcPass,
  }) => execute(
    CancelExternalExecutionRequest(
      executionId: executionId,
      rpcPass: rpcPass ?? this.rpcPass,
    ),
  );

  Future<ChainTxReceiptResponse> chainTxReceipt({
    required String coin,
    required String txHash,
    int? requiredConfirmations,
    String? rpcPass,
  }) => execute(
    ChainTxReceiptRequest(
      coin: coin,
      txHash: txHash,
      requiredConfirmations: requiredConfirmations,
      rpcPass: rpcPass ?? this.rpcPass,
    ),
  );

  Future<NewTaskResponse> initTradeRoute({
    required String routeExecutionId,
    required String idempotencyKey,
    required TradeRouteInitConsent routeConsent,
    String? rpcPass,
  }) => execute(
    TradeRouteInitRequest(
      routeExecutionId: routeExecutionId,
      idempotencyKey: idempotencyKey,
      routeConsent: routeConsent,
      rpcPass: rpcPass ?? this.rpcPass,
    ),
  );

  Future<TradeRouteTaskStatusResponse> tradeRouteStatus({
    required int taskId,
    bool forgetIfFinished = true,
    String? rpcPass,
  }) => execute(
    TradeRouteStatusRequest(
      taskId: taskId,
      forgetIfFinished: forgetIfFinished,
      rpcPass: rpcPass ?? this.rpcPass,
    ),
  );

  Future<RouteActionResponse> tradeRouteUserAction({
    required int taskId,
    required RouteExecutionUserAction userAction,
    String? rpcPass,
  }) => execute(
    TradeRouteUserActionRequest(
      taskId: taskId,
      userAction: userAction,
      rpcPass: rpcPass ?? this.rpcPass,
    ),
  );

  Future<RouteCancelResponse> cancelTradeRoute({
    required String routeExecutionId,
    String? rpcPass,
  }) => execute(
    CancelTradeRouteRequest(
      routeExecutionId: routeExecutionId,
      rpcPass: rpcPass ?? this.rpcPass,
    ),
  );
}
