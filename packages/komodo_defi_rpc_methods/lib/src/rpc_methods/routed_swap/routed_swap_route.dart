part of 'routed_swap_models.dart';

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
