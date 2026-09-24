import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// An amount of a token, as `routed_swap` reports it.
///
/// The token is identified by **either** a KDF [coin] ticker **or** a provider
/// [symbol] — exactly one of the two keys is present, and which one tells you
/// which you got. A symbol must never be treated as a tradable ticker: provider
/// symbols collide with real tickers (axlUSDC's on-chain symbol is frequently
/// `USDC`), so resolving one against the coin registry names the wrong asset.
///
/// The same rule covers `fee_costs[]` and a terminal `received`.
class RoutedSwapAmount extends Equatable {
  const RoutedSwapAmount({required this.amount, this.coin, this.symbol})
    : assert(
        coin != null || symbol != null,
        'a routed-swap amount must identify its token',
      );

  /// Parses `{coin|symbol, amount}`.
  factory RoutedSwapAmount.fromJson(JsonMap json) => RoutedSwapAmount(
    amount: json.value<String>('amount'),
    coin: json.valueOrNull<String>('coin'),
    symbol: json.valueOrNull<String>('symbol'),
  );

  /// Decimal string in coin units — never wei.
  final String amount;

  /// KDF ticker, when the token maps to one.
  final String? coin;

  /// The provider's token symbol, when it does not.
  final String? symbol;

  /// Whether this token can be looked up in the wallet's coin registry.
  ///
  /// When false the UI may show [symbol] as text but must not resolve it to an
  /// asset, link it to a balance, or offer it as something to trade.
  bool get isKnownAsset => coin != null;

  /// The best available label for display.
  String get label => coin ?? symbol!;

  /// Serialises back to the wire shape.
  JsonMap toJson() => {
    if (coin != null) 'coin': coin,
    if (symbol != null) 'symbol': symbol,
    'amount': amount,
  };

  @override
  List<Object?> get props => [amount, coin, symbol];
}

/// The executing tool for a route, e.g. Stargate V2.
///
/// Infrastructure identity: diagnostic, not customer-facing copy.
class RoutedSwapTool extends Equatable {
  const RoutedSwapTool({required this.key, required this.name, this.logoUrl});

  /// Parses `{key, name, logo_url?}`.
  factory RoutedSwapTool.fromJson(JsonMap json) => RoutedSwapTool(
    key: json.value<String>('key'),
    name: json.value<String>('name'),
    logoUrl: json.valueOrNull<String>('logo_url'),
  );

  /// Stable provider key, e.g. `stargateV2`.
  final String key;

  /// Human-readable name.
  final String name;

  /// Optional logo. Absent optional fields are omitted, not null.
  final String? logoUrl;

  /// Serialises back to the wire shape.
  JsonMap toJson() => {
    'key': key,
    'name': name,
    if (logoUrl != null) 'logo_url': logoUrl,
  };

  @override
  List<Object?> get props => [key, name, logoUrl];
}

/// One provider or protocol fee on a route.
class RoutedSwapFeeCost extends Equatable {
  const RoutedSwapFeeCost({
    required this.name,
    required this.amount,
    required this.included,
    this.amountUsd,
  });

  /// Parses a `fee_costs[]` entry.
  factory RoutedSwapFeeCost.fromJson(JsonMap json) => RoutedSwapFeeCost(
    name: json.value<String>('name'),
    amount: RoutedSwapAmount.fromJson(json),
    included: json.valueOrNull<bool>('included') ?? false,
    amountUsd: json.valueOrNull<String>('amount_usd'),
  );

  /// Free-text provider label.
  final String name;

  /// The fee token and amount.
  final RoutedSwapAmount amount;

  /// `true`: already deducted from the route's `to.amount`, so subtracting it
  /// again double-counts. `false`: charged in addition to the displayed
  /// amounts, and must be counted into total cost.
  final bool included;

  /// Optional provider-reported USD value.
  final String? amountUsd;

  /// Serialises back to the wire shape.
  JsonMap toJson() => {
    'name': name,
    ...amount.toJson(),
    if (amountUsd != null) 'amount_usd': amountUsd,
    'included': included,
  };

  @override
  List<Object?> get props => [name, amount, included, amountUsd];
}

/// Gas for one coin.
///
/// Used for the route's execution gas, the approval's gas, and the per-coin
/// totals. Approval gas never carries [amountUsd] — KDF computes it on-chain
/// and has no USD source — so a total for the coin paying approval gas omits
/// it too; fill it from the app's own price source rather than presenting a
/// partial sum as a total.
class RoutedSwapGasCost extends Equatable {
  const RoutedSwapGasCost({required this.amount, this.amountUsd});

  /// Parses a gas entry.
  factory RoutedSwapGasCost.fromJson(JsonMap json) => RoutedSwapGasCost(
    amount: RoutedSwapAmount.fromJson(json),
    amountUsd: json.valueOrNull<String>('amount_usd'),
  );

  /// The gas token and amount.
  final RoutedSwapAmount amount;

  /// Optional USD value.
  final String? amountUsd;

  /// Serialises back to the wire shape.
  JsonMap toJson() => {
    ...amount.toJson(),
    if (amountUsd != null) 'amount_usd': amountUsd,
  };

  @override
  List<Object?> get props => [amount, amountUsd];
}

/// Why a sell needs approval transactions.
enum RoutedSwapApprovalReason {
  /// No confirmed allowance covers the sell. One exact-amount approval.
  noAllowance('no_allowance'),

  /// A token that requires its allowance to pass through zero: a reset to
  /// zero, then the exact-amount approval. Two transactions.
  zeroReset('zero_reset'),

  /// A reason this build does not know.
  unknown('');

  const RoutedSwapApprovalReason(this.wire);

  /// Parses leniently.
  static RoutedSwapApprovalReason parse(String? value) => values.firstWhere(
    (reason) => reason.wire == value,
    orElse: () => RoutedSwapApprovalReason.unknown,
  );

  /// The wire value.
  final String wire;
}

/// The approval transactions a sell requires before the swap.
///
/// Present on a route only when approval is needed; omitted when the
/// confirmed allowance already covers the sell, and always omitted for a
/// native sell. An estimate that goes stale with the rest of the quote.
class RoutedSwapApproval extends Equatable {
  const RoutedSwapApproval({
    required this.required,
    required this.txCount,
    required this.reason,
    required this.spender,
    required this.gasCosts,
  });

  /// Parses `{required, tx_count, reason, spender, gas_costs}`.
  factory RoutedSwapApproval.fromJson(JsonMap json) => RoutedSwapApproval(
    required: json.valueOrNull<bool>('required') ?? true,
    txCount: json.valueOrNull<int>('tx_count') ?? 1,
    reason: RoutedSwapApprovalReason.parse(json.valueOrNull<String>('reason')),
    spender: json.valueOrNull<String>('spender') ?? '',
    gasCosts: _list(json, 'gas_costs', RoutedSwapGasCost.fromJson),
  );

  /// Always true when present in v1.
  final bool required;

  /// 1, or 2 when [reason] is [RoutedSwapApprovalReason.zeroReset].
  final int txCount;

  /// Why approval is needed.
  final RoutedSwapApprovalReason reason;

  /// The contract the approval grants to. KDF allowlists it independently.
  final String spender;

  /// Approval gas, additive to the route's execution gas. Never has USD.
  final List<RoutedSwapGasCost> gasCosts;

  /// Whether the current allowance is reset to zero before the exact approval.
  bool get resetsFirst => reason == RoutedSwapApprovalReason.zeroReset;

  /// Serialises back to the wire shape.
  JsonMap toJson() => {
    'required': required,
    'tx_count': txCount,
    'reason': reason.wire,
    'spender': spender,
    'gas_costs': [for (final gas in gasCosts) gas.toJson()],
  };

  @override
  List<Object?> get props => [required, txCount, reason, spender, gasCosts];
}

/// Kind of one route leg.
enum RoutedSwapStepType {
  /// A conversion on one chain.
  swap('swap'),

  /// A bridge between two chains.
  cross('cross'),

  /// A leg type this build does not know.
  unknown('');

  const RoutedSwapStepType(this.wire);

  /// Parses leniently.
  static RoutedSwapStepType parse(String value) => values.firstWhere(
    (type) => type.wire == value,
    orElse: () => RoutedSwapStepType.unknown,
  );

  /// The wire value.
  final String wire;
}

/// One leg of a route.
class RoutedSwapStep extends Equatable {
  const RoutedSwapStep({
    required this.type,
    required this.tool,
    this.chainId,
    this.fromChainId,
    this.toChainId,
  });

  /// Parses a `steps[]` entry.
  factory RoutedSwapStep.fromJson(JsonMap json) => RoutedSwapStep(
    type: json.value<String>('type'),
    tool: json.valueOrNull<String>('tool') ?? '',
    chainId: json.valueOrNull<int>('chain_id'),
    fromChainId: json.valueOrNull<int>('from_chain_id'),
    toChainId: json.valueOrNull<int>('to_chain_id'),
  );

  /// The raw `type`, kept so a leg type added later is still reportable.
  final String type;

  /// Provider key of the tool running this leg. Diagnostic only.
  final String tool;

  /// Set for same-chain legs.
  final int? chainId;

  /// Set for cross-chain legs.
  final int? fromChainId;

  /// Set for cross-chain legs.
  final int? toChainId;

  /// The parsed leg type.
  RoutedSwapStepType get stepType => RoutedSwapStepType.parse(type);

  /// Serialises back to the wire shape.
  JsonMap toJson() => {
    'type': type,
    'tool': tool,
    if (chainId != null) 'chain_id': chainId,
    if (fromChainId != null) 'from_chain_id': fromChainId,
    if (toChainId != null) 'to_chain_id': toChainId,
  };

  @override
  List<Object?> get props => [type, tool, chainId, fromChainId, toChainId];
}

/// A single route from `routed_swap::quote`, and the shape of
/// `executed_route` / `fresh_route` in task status.
///
/// v1 returns exactly one, but the response is an array so a route picker can
/// be added without a breaking change.
class RoutedSwapRoute extends Equatable {
  const RoutedSwapRoute({
    required this.provider,
    required this.from,
    required this.to,
    required this.toMinimum,
    required this.tool,
    required this.kind,
    required this.steps,
    required this.feeCosts,
    required this.gasCosts,
    required this.totalGasCosts,
    this.fromAddress,
    this.toAddress,
    this.approval,
    this.executionDurationS,
  });

  /// Parses one `routes[]` entry.
  factory RoutedSwapRoute.fromJson(JsonMap json) {
    final to = json.value<JsonMap>('to');
    final approval = json.valueOrNull<JsonMap>('approval');
    return RoutedSwapRoute(
      provider: json.valueOrNull<String>('provider') ?? 'lifi',
      from: RoutedSwapAmount.fromJson(json.value<JsonMap>('from')),
      to: RoutedSwapAmount.fromJson(to),
      toMinimum: RoutedSwapAmount(
        amount: to.value<String>('amount_min'),
        coin: to.valueOrNull<String>('coin'),
        symbol: to.valueOrNull<String>('symbol'),
      ),
      tool: RoutedSwapTool.fromJson(json.value<JsonMap>('tool')),
      kind: RoutedSwapRouteKind.parse(json.value<String>('kind')),
      fromAddress: json.valueOrNull<String>('from_address'),
      toAddress: json.valueOrNull<String>('to_address'),
      approval: approval == null ? null : RoutedSwapApproval.fromJson(approval),
      totalGasCosts: _list(json, 'total_gas_costs', RoutedSwapGasCost.fromJson),
      steps: _list(json, 'steps', RoutedSwapStep.fromJson),
      feeCosts: _list(json, 'fee_costs', RoutedSwapFeeCost.fromJson),
      gasCosts: _list(json, 'gas_costs', RoutedSwapGasCost.fromJson),
      executionDurationS: json.valueOrNull<int>('execution_duration_s'),
    );
  }

  /// Echoed provider, `lifi` in v1.
  final String provider;

  /// What the user sells.
  final RoutedSwapAmount from;

  /// Expected receive. **Do not headline this** — see [toMinimum].
  final RoutedSwapAmount to;

  /// The guaranteed floor after slippage.
  ///
  /// The contract instructs the GUI to display this ("you receive at least …")
  /// and to pass it to `init` as the guard. Leading with [to] overstates the
  /// outcome.
  final RoutedSwapAmount toMinimum;

  /// The executing tool. Diagnostic, not customer-facing copy.
  final RoutedSwapTool tool;

  /// Same-chain or cross-chain.
  final RoutedSwapRouteKind kind;

  /// The source coin's enabled address; funds are sent from it. Read-only in
  /// v1, and absent only on a KDF older than the contract.
  final String? fromAddress;

  /// Where the output lands. Always equals [fromAddress] in v1 (swaps send to
  /// self).
  final String? toAddress;

  /// Approval transactions required first, or null when none are.
  final RoutedSwapApproval? approval;

  /// Per-coin sums of [gasCosts] plus the approval's gas: the single network
  /// fee figure to display.
  final List<RoutedSwapGasCost> totalGasCosts;

  /// Per-leg breakdown.
  final List<RoutedSwapStep> steps;

  /// Provider and protocol fees.
  final List<RoutedSwapFeeCost> feeCosts;

  /// Execution gas for the swap itself, excluding approvals.
  final List<RoutedSwapGasCost> gasCosts;

  /// Provider's total duration estimate in seconds, when supplied.
  final int? executionDurationS;

  /// Serialises back to the wire shape. Used for support exports and to keep
  /// a record of exactly what was shown.
  JsonMap toJson() => {
    'provider': provider,
    'from': from.toJson(),
    'to': {...to.toJson(), 'amount_min': toMinimum.amount},
    'tool': tool.toJson(),
    'kind': kind.wire,
    if (fromAddress != null) 'from_address': fromAddress,
    if (toAddress != null) 'to_address': toAddress,
    if (approval != null) 'approval': approval!.toJson(),
    'total_gas_costs': [for (final gas in totalGasCosts) gas.toJson()],
    'steps': [for (final step in steps) step.toJson()],
    'fee_costs': [for (final fee in feeCosts) fee.toJson()],
    'gas_costs': [for (final gas in gasCosts) gas.toJson()],
    if (executionDurationS != null) 'execution_duration_s': executionDurationS,
  };

  @override
  List<Object?> get props => [
    provider,
    from,
    to,
    toMinimum,
    tool,
    kind,
    fromAddress,
    toAddress,
    approval,
    totalGasCosts,
    steps,
    feeCosts,
    gasCosts,
    executionDurationS,
  ];
}

/// Whether a route crosses chains.
enum RoutedSwapRouteKind {
  /// Completes in one transaction; no bridge phase.
  sameChain('same_chain'),

  /// Has a bridge phase, and can take 30+ minutes.
  crossChain('cross_chain'),

  /// A value this build does not know. Render generically rather than
  /// assuming same-chain, which would hide the bridge wait.
  unknown('');

  const RoutedSwapRouteKind(this.wire);

  /// Parses leniently — an unrecognised value is [unknown], not a throw.
  static RoutedSwapRouteKind parse(String value) => values.firstWhere(
    (kind) => kind.wire == value,
    orElse: () => RoutedSwapRouteKind.unknown,
  );

  /// The wire value.
  final String wire;
}

/// The in-progress ladder of `task::routed_swap::status`.
enum RoutedSwapState {
  /// KDF is re-quoting internally.
  fetchingQuote('FetchingQuote'),

  /// Reading the confirmed on-chain allowance.
  checkingAllowance('CheckingAllowance'),

  /// Sending an exact-amount ERC-20 approval (and a zero-reset first, when
  /// the token requires one).
  approving('Approving'),

  /// Signing locally. Still cancellable.
  signing('Signing'),

  /// Committed to the network transport. No longer cancellable.
  broadcasting('Broadcasting'),

  /// Waiting on source-chain confirmation.
  waitingSourceConfirmation('WaitingSourceConfirmation'),

  /// Following the bridge to the destination.
  trackingBridge('TrackingBridge'),

  /// A state this build does not know.
  ///
  /// Treated as a generic in-progress step. The alternative — throwing — would
  /// strand a user mid-swap on any KDF newer than the app.
  unknown('');

  const RoutedSwapState(this.wire);

  /// Parses leniently. Unknown values are [unknown].
  static RoutedSwapState parse(String value) => values.firstWhere(
    (state) => state.wire == value,
    orElse: () => RoutedSwapState.unknown,
  );

  /// The wire value.
  final String wire;

  /// Whether the transaction has been handed to the network.
  ///
  /// [unknown] answers **true**: refusing a cancel that might have worked is
  /// recoverable, offering one that cannot is not.
  bool get isPostBroadcast => switch (this) {
    RoutedSwapState.fetchingQuote ||
    RoutedSwapState.checkingAllowance ||
    RoutedSwapState.approving ||
    RoutedSwapState.signing => false,
    _ => true,
  };

  /// Whether `task::routed_swap::cancel` is accepted in this state.
  bool get isCancellable => !isPostBroadcast;
}

/// The KDF-owned bridge-tracking stage that drives display in
/// `TrackingBridge`.
///
/// Additive-only on the wire: an unrecognised value is [unknown], never a
/// throw.
enum RoutedSwapBridgeStage {
  /// Funds are moving between chains.
  bridging('bridging'),

  /// Waiting for delivery on the destination chain.
  destinationPending('destination_pending'),

  /// The bridge is refunding on the source chain.
  refundPending('refund_pending'),

  /// The user must act; carries an `action_url`. Not emitted in v1.
  actionRequired('action_required'),

  /// Stage not known yet, or a value this build does not recognise.
  unknown('unknown');

  const RoutedSwapBridgeStage(this.wire);

  /// Parses leniently; a missing value is [unknown].
  static RoutedSwapBridgeStage parse(String? value) => values.firstWhere(
    (stage) => stage.wire == value,
    orElse: () => RoutedSwapBridgeStage.unknown,
  );

  /// The wire value.
  final String wire;
}

/// The terminal `Ok` outcomes.
enum RoutedSwapOutcome {
  /// Delivered the requested coin at or above the accepted minimum.
  completed('completed'),

  /// Delivered on the destination chain, but below the minimum or as an
  /// intermediate token — see [RoutedSwapPartialReason].
  partial('partial'),

  /// Did not happen; funds returned on the source chain.
  refunded('refunded'),

  /// A value this build does not know. Must not be rendered as success.
  unknown('');

  const RoutedSwapOutcome(this.wire);

  /// Parses leniently. Unknown values are [unknown].
  static RoutedSwapOutcome parse(String value) => values.firstWhere(
    (outcome) => outcome.wire == value,
    orElse: () => RoutedSwapOutcome.unknown,
  );

  /// The wire value.
  final String wire;

  /// Whether this may be presented to the user as a completed swap.
  ///
  /// Only [completed] qualifies. `partial` and `refunded` must be surfaced
  /// prominently as *not* the swap the user asked for, and [unknown] is
  /// excluded because a future outcome the app cannot interpret must never
  /// default to "it worked".
  bool get isSuccess => this == RoutedSwapOutcome.completed;
}

/// Why an outcome is `partial`.
enum RoutedSwapPartialReason {
  /// The requested token arrived, but below the accepted minimum.
  belowMinimum('below_minimum'),

  /// A different (intermediate) token arrived instead of the requested one.
  intermediateToken('intermediate_token'),

  /// A reason this build does not know.
  unknown('');

  const RoutedSwapPartialReason(this.wire);

  /// Parses leniently.
  static RoutedSwapPartialReason parse(String? value) => values.firstWhere(
    (reason) => reason.wire == value,
    orElse: () => RoutedSwapPartialReason.unknown,
  );

  /// The wire value.
  final String wire;
}

/// The `{status, details}` payload of `task::routed_swap::status`, and the
/// `swap` object of a `routed_swap::history` entry — one shape for a running
/// swap and a stored one.
///
/// Every variant carries [uuid] and [provider]: the uuid is the only durable
/// handle on a swap, since `task_id` is in-memory and dies on restart,
/// cancellation or a `forget_if_finished` read. [executedRoute] is present on
/// every payload after `FetchingQuote` completes: the fresh, internally
/// fetched route actually being executed, which may differ from the route
/// shown before `init`.
sealed class RoutedSwapStatus extends Equatable {
  const RoutedSwapStatus({
    required this.uuid,
    required this.provider,
    this.executedRoute,
  });

  /// Parses the `details` object for a given task [status].
  factory RoutedSwapStatus.parse(String status, JsonMap details) {
    final uuid = details.value<String>('uuid');
    final provider = details.valueOrNull<String>('provider') ?? 'lifi';
    final route = details.valueOrNull<JsonMap>('executed_route');
    final executedRoute = route == null
        ? null
        : RoutedSwapRoute.fromJson(route);

    switch (status) {
      case 'Ok':
        return RoutedSwapFinished(
          uuid: uuid,
          provider: provider,
          executedRoute: executedRoute,
          outcome: RoutedSwapOutcome.parse(details.value<String>('outcome')),
          partialReason: details.valueOrNull<String>('partial_reason') == null
              ? null
              : RoutedSwapPartialReason.parse(
                  details.valueOrNull<String>('partial_reason'),
                ),
          received: RoutedSwapAmount.fromJson(
            details.value<JsonMap>('received'),
          ),
          sourceTxHash: details.valueOrNull<String>('source_tx_hash'),
          destTxHash: details.valueOrNull<String>('dest_tx_hash'),
          providerExplorerUrl: details.valueOrNull<String>(
            'provider_explorer_url',
          ),
        );
      case 'Error':
        final errorType = details.valueOrNull<String>('error_type') ?? '';
        final data = details['error_data'];
        return RoutedSwapErrored(
          uuid: uuid,
          provider: provider,
          executedRoute: executedRoute,
          errorType: errorType,
          message: details.valueOrNull<String>('error') ?? errorType,
          error: RoutedSwapTaskError.parse(
            errorType,
            data is Map ? convertToJsonMap(data) : const {},
          ),
        );
      default:
        final rawStage = details.valueOrNull<String>('stage');
        return RoutedSwapInProgress(
          uuid: uuid,
          provider: provider,
          executedRoute: executedRoute,
          state: RoutedSwapState.parse(details.value<String>('state')),
          rawState: details.value<String>('state'),
          approveTxHash: details.valueOrNull<String>('approve_tx_hash'),
          // `tx_hash` was the pre-release name of this field; reading it as a
          // fallback keeps an older engine from losing the source hash.
          sourceTxHash:
              details.valueOrNull<String>('source_tx_hash') ??
              details.valueOrNull<String>('tx_hash'),
          stage: rawStage == null
              ? null
              : RoutedSwapBridgeStage.parse(rawStage),
          rawStage: rawStage,
          substatus: details.valueOrNull<String>('substatus'),
          substatusMessage: details.valueOrNull<String>('substatus_message'),
          providerExplorerUrl: details.valueOrNull<String>(
            'provider_explorer_url',
          ),
          executionDurationS: details.valueOrNull<int>('execution_duration_s'),
          actionUrl: details.valueOrNull<String>('action_url'),
        );
    }
  }

  /// The persistent swap id. Survives restart; recoverable via history.
  final String uuid;

  /// Echoed provider.
  final String provider;

  /// The route actually being executed, once `FetchingQuote` has completed.
  final RoutedSwapRoute? executedRoute;

  /// Whether the task has reached a terminal state.
  bool get isTerminal => this is! RoutedSwapInProgress;

  @override
  List<Object?> get props => [uuid, provider, executedRoute];
}

/// A swap still running.
final class RoutedSwapInProgress extends RoutedSwapStatus {
  const RoutedSwapInProgress({
    required super.uuid,
    required super.provider,
    required this.state,
    required this.rawState,
    super.executedRoute,
    this.approveTxHash,
    this.sourceTxHash,
    this.stage,
    this.rawStage,
    this.substatus,
    this.substatusMessage,
    this.providerExplorerUrl,
    this.executionDurationS,
    this.actionUrl,
  });

  /// The parsed state.
  final RoutedSwapState state;

  /// The raw `state` string, kept so an unknown value can still be logged and
  /// reported to support rather than silently flattened.
  final String rawState;

  /// On `Approving`, once the approval transaction has been broadcast.
  final String? approveTxHash;

  /// The source-chain transaction: optional on `Broadcasting` (its presence
  /// does not confirm network acceptance), present from
  /// `WaitingSourceConfirmation` on.
  final String? sourceTxHash;

  /// The bridge stage, on `TrackingBridge`.
  final RoutedSwapBridgeStage? stage;

  /// The raw `stage` string, for logs.
  final String? rawStage;

  /// Opaque provider passthrough. Not localizable — show it in a details
  /// disclosure, never as primary copy.
  final String? substatus;

  /// Opaque provider passthrough, in the provider's own language.
  final String? substatusMessage;

  /// Provider explorer link for the bridge.
  final String? providerExplorerUrl;

  /// Provider duration estimate, when supplied.
  final int? executionDurationS;

  /// Where the user must act, when [stage] is `action_required`.
  final String? actionUrl;

  @override
  List<Object?> get props => [
    ...super.props,
    state,
    rawState,
    approveTxHash,
    sourceTxHash,
    stage,
    rawStage,
    substatus,
    substatusMessage,
    providerExplorerUrl,
    executionDurationS,
    actionUrl,
  ];
}

/// A swap that reached a terminal `Ok`.
///
/// `Ok` is not the same as "succeeded" — check [RoutedSwapOutcome.isSuccess].
final class RoutedSwapFinished extends RoutedSwapStatus {
  const RoutedSwapFinished({
    required super.uuid,
    required super.provider,
    required this.outcome,
    required this.received,
    super.executedRoute,
    this.partialReason,
    this.sourceTxHash,
    this.destTxHash,
    this.providerExplorerUrl,
  });

  /// What actually happened.
  final RoutedSwapOutcome outcome;

  /// Why the outcome is partial. Set only for [RoutedSwapOutcome.partial].
  final RoutedSwapPartialReason? partialReason;

  /// The token and amount the user actually received. For a refund this is the
  /// returned source coin, not the requested destination coin. For a
  /// same-chain swap it is the executed route's quoted `to.amount`.
  final RoutedSwapAmount received;

  /// Source-chain transaction.
  final String? sourceTxHash;

  /// Destination-chain transaction. Absent for refunds and same-chain swaps.
  final String? destTxHash;

  /// Provider explorer link.
  final String? providerExplorerUrl;

  @override
  List<Object?> get props => [
    ...super.props,
    outcome,
    partialReason,
    received,
    sourceTxHash,
    destTxHash,
    providerExplorerUrl,
  ];
}

/// A swap that ended in a terminal `Error`.
final class RoutedSwapErrored extends RoutedSwapStatus {
  const RoutedSwapErrored({
    required super.uuid,
    required super.provider,
    required this.errorType,
    required this.message,
    required this.error,
    super.executedRoute,
  });

  /// The `error_type` discriminator, kept as a string so an unrecognised
  /// variant still renders instead of throwing.
  final String errorType;

  /// KDF's human-readable error text. Diagnostic; not localized.
  final String message;

  /// The typed payload.
  final RoutedSwapTaskError error;

  @override
  List<Object?> get props => [...super.props, errorType, message, error];
}

/// Why an approval failed.
enum RoutedSwapApprovalFailureReason {
  /// The approval could not be broadcast.
  approvalBroadcastFailed('approval_broadcast_failed'),

  /// The approval transaction failed or did not confirm in time.
  approvalTransactionFailed('approval_transaction_failed'),

  /// The zero-reset never confirmed.
  allowanceResetNotConfirmed('allowance_reset_not_confirmed'),

  /// The confirmed allowance remained insufficient after recheck.
  confirmedAllowanceInsufficient('confirmed_allowance_insufficient'),

  /// A reason this build does not know.
  unknown('');

  const RoutedSwapApprovalFailureReason(this.wire);

  /// Parses leniently.
  static RoutedSwapApprovalFailureReason parse(String? value) =>
      values.firstWhere(
        (reason) => reason.wire == value,
        orElse: () => RoutedSwapApprovalFailureReason.unknown,
      );

  /// The wire value.
  final String wire;
}

/// Why the source transaction failed.
enum RoutedSwapTxFailureReason {
  /// The source transaction reverted; funds (minus gas) never left.
  sourceTransactionReverted('source_transaction_reverted'),

  /// Broadcast, but not confirmed within KDF's wait. It may still confirm —
  /// never state that funds did not move.
  sourceTransactionNotConfirmed('source_transaction_not_confirmed'),

  /// A reason this build does not know.
  unknown('');

  const RoutedSwapTxFailureReason(this.wire);

  /// Parses leniently.
  static RoutedSwapTxFailureReason parse(String? value) => values.firstWhere(
    (reason) => reason.wire == value,
    orElse: () => RoutedSwapTxFailureReason.unknown,
  );

  /// The wire value.
  final String wire;
}

/// Why an external wallet did not sign. Unreachable for local-key coins.
enum RoutedSwapSigningRejectionReason {
  /// The wallet declined.
  userRejected('user_rejected'),

  /// The wallet did not answer before the request expired.
  timeout('timeout'),

  /// The wallet supports neither signing method.
  unsupportedMethod('unsupported_method'),

  /// A reason this build does not know.
  unknown('');

  const RoutedSwapSigningRejectionReason(this.wire);

  /// Parses leniently.
  static RoutedSwapSigningRejectionReason parse(String? value) =>
      values.firstWhere(
        (reason) => reason.wire == value,
        orElse: () => RoutedSwapSigningRejectionReason.unknown,
      );

  /// The wire value.
  final String wire;
}

/// Which pre-sign safety check rejected a route.
enum RoutedSwapPreflightCheck {
  /// The call simulation failed. A retry is reasonable (often a stale route).
  simulation('simulation'),

  /// The execution target is not allowlisted. Do not retry; report.
  targetAllowlist('target_allowlist'),

  /// The approval spender is not allowlisted. Do not retry; report.
  spenderAllowlist('spender_allowlist'),

  /// The native value breached the exact-value cap. A re-quote may differ.
  valueCap('value_cap'),

  /// The amounts breached safety bounds. A re-quote may differ.
  amountBounds('amount_bounds'),

  /// The gas breached safety bounds. A re-quote may differ.
  gasBounds('gas_bounds'),

  /// A check this build does not know.
  unknown('');

  const RoutedSwapPreflightCheck(this.wire);

  /// Parses leniently.
  static RoutedSwapPreflightCheck parse(String? value) => values.firstWhere(
    (check) => check.wire == value,
    orElse: () => RoutedSwapPreflightCheck.unknown,
  );

  /// The wire value.
  final String wire;

  /// Whether retrying the same swap is a reasonable next step.
  bool get isRetryable => this == RoutedSwapPreflightCheck.simulation;

  /// Whether a fresh quote may produce a route that passes.
  bool get mayPassOnRequote => switch (this) {
    RoutedSwapPreflightCheck.simulation ||
    RoutedSwapPreflightCheck.valueCap ||
    RoutedSwapPreflightCheck.amountBounds ||
    RoutedSwapPreflightCheck.gasBounds => true,
    _ => false,
  };
}

/// The typed `error_data` of a terminal routed-swap `Error`.
///
/// One variant per row of the contract's terminal-error table, plus the two
/// outcomes reachable only through history (`TaskCancelled`,
/// `AbortedOnRestart`) and an [RoutedSwapUnknownTaskError] fallback that keeps
/// the raw payload so a newer engine never crashes an older app.
sealed class RoutedSwapTaskError extends Equatable {
  const RoutedSwapTaskError();

  /// Parses [data] for [errorType].
  factory RoutedSwapTaskError.parse(String errorType, JsonMap data) {
    String? str(String key) => data.valueOrNull<String>(key);
    String req(String key) => data.valueOrNull<String>(key) ?? '';
    return switch (errorType) {
      'QuoteWorsened' => RoutedSwapQuoteWorsenedError(
        freshRoute: data.valueOrNull<JsonMap>('fresh_route') == null
            ? null
            : RoutedSwapRoute.fromJson(data.value<JsonMap>('fresh_route')),
      ),
      'InsufficientBalance' => RoutedSwapInsufficientBalanceError(
        coin: req('coin'),
        available: req('available'),
        required: req('required'),
      ),
      'ApprovalFailed' => RoutedSwapApprovalFailedError(
        reason: RoutedSwapApprovalFailureReason.parse(str('reason')),
      ),
      'SwapTxFailed' => RoutedSwapTxFailedError(
        sourceTxHash: str('source_tx_hash') ?? str('tx_hash'),
        reason: RoutedSwapTxFailureReason.parse(str('reason')),
      ),
      'SigningRejected' => RoutedSwapSigningRejectedError(
        reason: RoutedSwapSigningRejectionReason.parse(str('reason')),
      ),
      'BridgeFailed' => RoutedSwapBridgeFailedError(
        sourceTxHash: str('source_tx_hash') ?? str('tx_hash'),
        substatus: str('substatus'),
        substatusMessage: str('substatus_message'),
        providerExplorerUrl: str('provider_explorer_url'),
        providerRequestId: str('provider_request_id'),
      ),
      'PreflightRejected' => RoutedSwapPreflightRejectedError(
        check: RoutedSwapPreflightCheck.parse(str('check')),
      ),
      'NoRouteFound' => RoutedSwapNoRouteTaskError(
        reasons: _strings(data, 'reasons'),
        providerRequestId: str('provider_request_id'),
      ),
      'RateLimited' => RoutedSwapRateLimitedTaskError(
        providerRequestId: str('provider_request_id'),
      ),
      'ProviderApiError' => RoutedSwapProviderTaskError(
        message: req('message'),
        providerRequestId: str('provider_request_id'),
      ),
      'AmountOutOfBounds' => RoutedSwapAmountOutOfBoundsTaskError(
        param: req('param'),
        value: req('value'),
        min: req('min'),
        max: req('max'),
      ),
      'AbortedOnRestart' => const RoutedSwapAbortedOnRestartError(),
      'TaskCancelled' => const RoutedSwapTaskCancelledError(),
      'InternalError' => RoutedSwapInternalTaskError(message: req('message')),
      'TransportError' => RoutedSwapTransportTaskError(message: req('message')),
      _ => RoutedSwapUnknownTaskError(errorType: errorType, data: data),
    };
  }

  /// The wire `error_type`.
  String get errorType;

  /// The provider's support-correlation id, on provider-originated errors.
  String? get providerRequestId => null;

  /// Whether the contract says this error happened before anything could be
  /// broadcast — for the swap itself. An approval may still have confirmed
  /// earlier; check the approval evidence separately.
  ///
  /// Conservative: an error the contract does not pin as pre-broadcast
  /// answers false.
  bool get isPreBroadcast => false;
}

/// The fresh route came in below the accepted minimum. Nothing was sent.
final class RoutedSwapQuoteWorsenedError extends RoutedSwapTaskError {
  const RoutedSwapQuoteWorsenedError({this.freshRoute});

  /// The re-priced route, to show old versus new and retry `init` with its
  /// minimum.
  final RoutedSwapRoute? freshRoute;

  @override
  String get errorType => 'QuoteWorsened';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => [freshRoute];
}

/// Not enough balance on the source chain, including routed execution gas and
/// any required approval gas.
final class RoutedSwapInsufficientBalanceError extends RoutedSwapTaskError {
  const RoutedSwapInsufficientBalanceError({
    required this.coin,
    required this.available,
    required this.required,
  });

  /// The coin that ran short.
  final String coin;

  /// What was available, in coin units.
  final String available;

  /// What was required, in coin units.
  final String required;

  @override
  String get errorType => 'InsufficientBalance';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => [coin, available, required];
}

/// The approval failed. Nothing was swapped, but approval gas may be spent.
final class RoutedSwapApprovalFailedError extends RoutedSwapTaskError {
  const RoutedSwapApprovalFailedError({required this.reason});

  /// Why.
  final RoutedSwapApprovalFailureReason reason;

  @override
  String get errorType => 'ApprovalFailed';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => [reason];
}

/// The source transaction failed.
final class RoutedSwapTxFailedError extends RoutedSwapTaskError {
  const RoutedSwapTxFailedError({required this.reason, this.sourceTxHash});

  /// The source transaction.
  final String? sourceTxHash;

  /// Reverted, or not confirmed in time.
  final RoutedSwapTxFailureReason reason;

  /// Whether the transaction may still confirm, so the funds may yet move.
  bool get mayStillConfirm =>
      reason != RoutedSwapTxFailureReason.sourceTransactionReverted;

  @override
  String get errorType => 'SwapTxFailed';

  @override
  List<Object?> get props => [sourceTxHash, reason];
}

/// An external wallet did not sign. Unreachable for local-key coins.
final class RoutedSwapSigningRejectedError extends RoutedSwapTaskError {
  const RoutedSwapSigningRejectedError({required this.reason});

  /// Why.
  final RoutedSwapSigningRejectionReason reason;

  @override
  String get errorType => 'SigningRejected';

  // A timeout after Broadcasting began may have broadcast without KDF
  // receiving a hash, so only an explicit decline proves nothing went out.
  @override
  bool get isPreBroadcast => reason != RoutedSwapSigningRejectionReason.timeout;

  @override
  List<Object?> get props => [reason];
}

/// The provider reported FAILED without refund resolution. Funds left the
/// source chain; direct the user to the explorer link and support.
final class RoutedSwapBridgeFailedError extends RoutedSwapTaskError {
  const RoutedSwapBridgeFailedError({
    this.sourceTxHash,
    this.substatus,
    this.substatusMessage,
    this.providerExplorerUrl,
    this.providerRequestId,
  });

  /// The source transaction.
  final String? sourceTxHash;

  /// Opaque provider passthrough.
  final String? substatus;

  /// Opaque provider passthrough.
  final String? substatusMessage;

  /// Provider explorer link.
  final String? providerExplorerUrl;

  @override
  final String? providerRequestId;

  @override
  String get errorType => 'BridgeFailed';

  @override
  List<Object?> get props => [
    sourceTxHash,
    substatus,
    substatusMessage,
    providerExplorerUrl,
    providerRequestId,
  ];
}

/// A pre-sign safety check failed. Nothing was sent.
final class RoutedSwapPreflightRejectedError extends RoutedSwapTaskError {
  const RoutedSwapPreflightRejectedError({required this.check});

  /// Which check.
  final RoutedSwapPreflightCheck check;

  @override
  String get errorType => 'PreflightRejected';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => [check];
}

/// The internal fresh quote found no route. Nothing was sent.
final class RoutedSwapNoRouteTaskError extends RoutedSwapTaskError {
  const RoutedSwapNoRouteTaskError({
    this.reasons = const [],
    this.providerRequestId,
  });

  /// Display strings with no stable format. Never parse them.
  final List<String> reasons;

  @override
  final String? providerRequestId;

  @override
  String get errorType => 'NoRouteFound';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => [reasons, providerRequestId];
}

/// The provider's quota was exhausted during the internal re-quote. Nothing
/// was sent.
final class RoutedSwapRateLimitedTaskError extends RoutedSwapTaskError {
  const RoutedSwapRateLimitedTaskError({this.providerRequestId});

  @override
  final String? providerRequestId;

  @override
  String get errorType => 'RateLimited';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => [providerRequestId];
}

/// The provider errored during the internal re-quote. Nothing was sent.
final class RoutedSwapProviderTaskError extends RoutedSwapTaskError {
  const RoutedSwapProviderTaskError({
    required this.message,
    this.providerRequestId,
  });

  /// Sanitized provider failure. Diagnostic.
  final String message;

  @override
  final String? providerRequestId;

  @override
  String get errorType => 'ProviderApiError';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => [message, providerRequestId];
}

/// The amount fell outside the fresh route's bounds. Nothing was sent.
final class RoutedSwapAmountOutOfBoundsTaskError extends RoutedSwapTaskError {
  const RoutedSwapAmountOutOfBoundsTaskError({
    required this.param,
    required this.value,
    required this.min,
    required this.max,
  });

  /// The offending parameter.
  final String param;

  /// Its value.
  final String value;

  /// The lower bound.
  final String min;

  /// The upper bound.
  final String max;

  @override
  String get errorType => 'AmountOutOfBounds';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => [param, value, min, max];
}

/// KDF restarted before `Broadcasting`. Nothing executed, though an already
/// confirmed exact approval may remain. History only.
final class RoutedSwapAbortedOnRestartError extends RoutedSwapTaskError {
  const RoutedSwapAbortedOnRestartError();

  @override
  String get errorType => 'AbortedOnRestart';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => const [];
}

/// The user cancelled before `Broadcasting`. An approval already confirmed
/// cannot be undone. History only.
final class RoutedSwapTaskCancelledError extends RoutedSwapTaskError {
  const RoutedSwapTaskCancelledError();

  @override
  String get errorType => 'TaskCancelled';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => const [];
}

/// An internal failure. Terminal before `Broadcasting`, except the rare
/// external-wallet handoff failure — so not provably pre-broadcast from the
/// payload alone.
final class RoutedSwapInternalTaskError extends RoutedSwapTaskError {
  const RoutedSwapInternalTaskError({required this.message});

  /// Diagnostic text.
  final String message;

  @override
  String get errorType => 'InternalError';

  @override
  List<Object?> get props => [message];
}

/// A transport failure before `Broadcasting`. After broadcast, transport
/// problems keep the task tracking instead of failing.
final class RoutedSwapTransportTaskError extends RoutedSwapTaskError {
  const RoutedSwapTransportTaskError({required this.message});

  /// Diagnostic text.
  final String message;

  @override
  String get errorType => 'TransportError';

  @override
  bool get isPreBroadcast => true;

  @override
  List<Object?> get props => [message];
}

/// An `error_type` this build does not know. Never assumed pre-broadcast.
final class RoutedSwapUnknownTaskError extends RoutedSwapTaskError {
  const RoutedSwapUnknownTaskError({
    required this.errorType,
    this.data = const {},
  });

  @override
  final String errorType;

  /// The raw payload, for logs and support.
  final JsonMap data;

  @override
  String? get providerRequestId =>
      data.valueOrNull<String>('provider_request_id');

  @override
  List<Object?> get props => [errorType, data];
}

/// One activated coin eligible to attempt a quote.
class RoutedSwapSupportedCoin extends Equatable {
  const RoutedSwapSupportedCoin({required this.coin, required this.chainId});

  /// Parses a `coins[]` entry.
  factory RoutedSwapSupportedCoin.fromJson(JsonMap json) =>
      RoutedSwapSupportedCoin(
        coin: json.value<String>('coin'),
        chainId: json.value<int>('chain_id'),
      );

  /// KDF ticker.
  final String coin;

  /// EVM chain id.
  final int chainId;

  @override
  List<Object?> get props => [coin, chainId];
}

List<T> _list<T>(JsonMap json, String key, T Function(JsonMap) parse) => [
  for (final entry in json.valueOrNull<List<dynamic>>(key) ?? const [])
    if (entry is Map) parse(convertToJsonMap(entry)),
];

List<String> _strings(JsonMap json, String key) => [
  for (final entry in json.valueOrNull<List<dynamic>>(key) ?? const [])
    if (entry is String) entry,
];
