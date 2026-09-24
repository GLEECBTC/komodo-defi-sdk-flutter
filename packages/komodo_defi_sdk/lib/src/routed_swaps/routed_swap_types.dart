import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;
import 'package:komodo_defi_sdk/src/routed_swaps/routed_swap_value.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// What a routed swap will cost, as one list.
///
/// The wire contract splits costs into provider `fee_costs`, execution
/// `gas_costs` and the approval's `gas_costs`, each with its own inclusion
/// rules. Reconciling them correctly is easy to get wrong and the mistake is a
/// wrong number in front of a user, so the SDK does it once here.
class RoutedSwapCost with RoutedSwapValue {
  /// Creates a reconciled cost line.
  const RoutedSwapCost({
    required this.label,
    required this.amount,
    required this.kind,
    required this.isDeductedFromReceive,
    this.assetId,
    this.symbol,
    this.usdValue,
  });

  /// Provider label for a fee; a fixed label for gas. Diagnostic.
  final String label;

  /// How much, in units of the cost's own token.
  final Decimal amount;

  /// What kind of cost this is.
  final RoutedSwapCostKind kind;

  /// Whether this is already subtracted from the receive amount.
  ///
  /// When true, showing it as an additional line item double-counts it.
  final bool isDeductedFromReceive;

  /// The wallet asset this cost is denominated in, when it maps to one.
  final AssetId? assetId;

  /// The provider's token symbol, when the token is not a wallet asset.
  ///
  /// Display-only. Never resolve it against the coin registry: provider
  /// symbols collide with real tickers.
  final String? symbol;

  /// USD value, when the provider supplied one. Never present on approval gas.
  final Decimal? usdValue;

  /// A label for the token this cost is paid in.
  String get tokenLabel => assetId?.id ?? symbol ?? '';

  @override
  List<Object?> get props => [
    label,
    amount,
    kind,
    isDeductedFromReceive,
    assetId,
    symbol,
    usdValue,
  ];
}

/// The kind of a [RoutedSwapCost].
enum RoutedSwapCostKind {
  /// Charged by the aggregator or a protocol along the route.
  providerFee,

  /// Chain gas for the swap transaction itself.
  gas,

  /// Chain gas for the approval transaction(s) that precede the swap.
  approvalGas,
}

/// The single network-fee figure for one coin: execution gas plus any
/// approval gas.
class RoutedSwapNetworkFee with RoutedSwapValue {
  /// Creates a per-coin network fee total.
  const RoutedSwapNetworkFee({
    required this.ticker,
    required this.amount,
    this.assetId,
    this.usdValue,
  });

  /// The gas coin's KDF ticker.
  final String ticker;

  /// The wallet asset, when the ticker maps to one.
  final AssetId? assetId;

  /// How much, in coin units.
  final Decimal amount;

  /// USD value, present only when every contributing row carried one — so it
  /// is absent for the coin paying approval gas. Fill it from a price source
  /// rather than presenting a partial sum.
  final Decimal? usdValue;

  @override
  List<Object?> get props => [ticker, assetId, amount, usdValue];
}

/// The approval transactions a sell needs before the swap.
class RoutedSwapApprovalInfo with RoutedSwapValue {
  /// Creates the approval description.
  const RoutedSwapApprovalInfo({
    required this.txCount,
    required this.resetsFirst,
    required this.spender,
  });

  /// One, or two when the allowance is reset to zero first.
  final int txCount;

  /// Whether the current allowance is reset to zero before the exact
  /// approval.
  final bool resetsFirst;

  /// The contract the exact approval grants to.
  final String spender;

  @override
  List<Object?> get props => [txCount, resetsFirst, spender];
}

/// One leg of a route: a conversion on one chain, or a bridge between two.
class RoutedSwapLeg with RoutedSwapValue {
  /// Creates a leg.
  const RoutedSwapLeg({
    required this.type,
    this.chainId,
    this.fromChainId,
    this.toChainId,
  });

  /// Swap, cross, or a type added later.
  final rpc.RoutedSwapStepType type;

  /// EVM chain id of a same-chain leg.
  final int? chainId;

  /// EVM chain id a bridge leg leaves.
  final int? fromChainId;

  /// EVM chain id a bridge leg arrives on.
  final int? toChainId;

  @override
  List<Object?> get props => [type, chainId, fromChainId, toChainId];
}

/// A priced route that is ready to execute.
///
/// Carries its own execution guard, so starting a swap never requires the
/// caller to re-derive `min_to_amount`. Passing the *expected* receive as the
/// guard instead of the guaranteed minimum would reject nearly every swap, and
/// that footgun is removed by construction: `RoutedSwapManager.start` takes an
/// offer, not loose numbers.
class RoutedSwapOffer with RoutedSwapValue {
  /// Wraps a parsed route with the context needed to execute and display it.
  const RoutedSwapOffer({
    required this.from,
    required this.to,
    required this.sellAmount,
    required this.expectedReceive,
    required this.guaranteedReceive,
    required this.kind,
    required this.costs,
    required this.networkFees,
    required this.legs,
    required this.quotedAt,
    required this.provider,
    required this.toolKey,
    required this.toolName,
    required this.route,
    this.order,
    this.fromAddress,
    this.toAddress,
    this.approval,
    this.toolLogoUrl,
    this.estimatedDuration,
    this.slippage,
  });

  /// The asset being sold.
  final AssetId from;

  /// The asset being bought.
  final AssetId to;

  /// How much of [from] is spent.
  final Decimal sellAmount;

  /// The likely receive amount. Informational.
  final Decimal expectedReceive;

  /// The amount the user is guaranteed to receive at minimum.
  ///
  /// **This is the number to show.** It is also the value enforced when the
  /// swap runs: if a fresh quote falls below it, nothing is sent on-chain.
  final Decimal guaranteedReceive;

  /// Same-chain, cross-chain, or a kind this build does not know.
  final rpc.RoutedSwapRouteKind kind;

  /// Provider fees, execution gas and approval gas, already reconciled.
  final List<RoutedSwapCost> costs;

  /// The network fee to display, per gas coin — execution plus approval gas.
  final List<RoutedSwapNetworkFee> networkFees;

  /// The route's legs, for describing how it completes.
  final List<RoutedSwapLeg> legs;

  /// When this offer was priced.
  final DateTime quotedAt;

  /// The aggregator that priced this route. Diagnostic.
  final String provider;

  /// Stable key of the executing tool. Diagnostic.
  final String toolKey;

  /// Name of the executing tool. Diagnostic: infrastructure identity is not
  /// customer-facing copy.
  final String toolName;

  /// Logo for [toolName], when the provider supplied one.
  final String? toolLogoUrl;

  /// The route order this offer was priced with. `start` passes it on so the
  /// engine's internal re-quote targets the same route.
  final rpc.RoutedSwapOrder? order;

  /// The address funds are sent from: the source coin's enabled address.
  final String? fromAddress;

  /// Where the output lands. Equals [fromAddress] in v1.
  final String? toAddress;

  /// Approval transactions required before the swap, or null when none are.
  final RoutedSwapApprovalInfo? approval;

  /// Provider estimate for the whole route.
  final Duration? estimatedDuration;

  /// The slippage tolerance this offer was priced at, when not the default.
  final double? slippage;

  /// The raw route, kept so exports and diagnostics reproduce exactly what was
  /// shown.
  final rpc.RoutedSwapRoute route;

  /// Whether the route crosses chains, and therefore has a bridge wait that
  /// can run to tens of minutes. An unknown kind answers true: hiding a bridge
  /// wait is worse than announcing one that does not come.
  bool get isCrossChain => kind != rpc.RoutedSwapRouteKind.sameChain;

  /// Whether executing requires approval transactions first.
  bool get requiresApproval => approval != null;

  /// How much of the receive amount is at risk to price movement.
  Decimal get slippageAllowance => expectedReceive - guaranteedReceive;

  /// Whether this offer is old enough that it should be re-priced.
  ///
  /// Quotes go stale in roughly one to two minutes and carry no reservation,
  /// so this is a display hint, not a guarantee.
  bool isStaleAt(
    DateTime now, {
    Duration maxAge = const Duration(seconds: 60),
  }) => now.difference(quotedAt) >= maxAge;

  /// Provider fees charged on top of the sell amount, per token.
  ///
  /// Fees already deducted from the receive amount are excluded, because
  /// adding them would charge the user twice in the UI. Gas is not included:
  /// read [networkFees] for it. A provider symbol is keyed apart from a wallet
  /// asset with the same text, so the two never merge.
  Map<String, Decimal> get additionalFeesByToken {
    final totals = <String, Decimal>{};
    for (final cost in costs) {
      if (cost.kind != RoutedSwapCostKind.providerFee) continue;
      if (cost.isDeductedFromReceive) continue;
      final key = cost.assetId?.id ?? 'symbol:${cost.symbol}';
      totals[key] = (totals[key] ?? Decimal.zero) + cost.amount;
    }
    return totals;
  }

  /// A copy re-stamped with [quotedAt].
  RoutedSwapOffer copyWith({DateTime? quotedAt}) => RoutedSwapOffer(
    from: from,
    to: to,
    sellAmount: sellAmount,
    expectedReceive: expectedReceive,
    guaranteedReceive: guaranteedReceive,
    kind: kind,
    costs: costs,
    networkFees: networkFees,
    legs: legs,
    quotedAt: quotedAt ?? this.quotedAt,
    provider: provider,
    toolKey: toolKey,
    toolName: toolName,
    toolLogoUrl: toolLogoUrl,
    route: route,
    order: order,
    fromAddress: fromAddress,
    toAddress: toAddress,
    approval: approval,
    estimatedDuration: estimatedDuration,
    slippage: slippage,
  );

  @override
  List<Object?> get props => [
    from,
    to,
    sellAmount,
    expectedReceive,
    guaranteedReceive,
    kind,
    costs,
    networkFees,
    legs,
    quotedAt,
    provider,
    toolKey,
    toolName,
    toolLogoUrl,
    route,
    order,
    fromAddress,
    toAddress,
    approval,
    estimatedDuration,
    slippage,
  ];
}

/// The largest amount that can be sold while keeping the source chain's gas.
class RoutedSwapMaxSell with RoutedSwapValue {
  /// Creates a max-sell result.
  const RoutedSwapMaxSell({
    required this.amount,
    required this.reservedForFees,
    this.feeAsset,
  });

  /// What may be sold. Zero when the balance cannot even cover the gas.
  final Decimal amount;

  /// What was held back for network fees, in [feeAsset] units. Zero for a
  /// token sell, whose gas is paid in the chain's native coin.
  final Decimal reservedForFees;

  /// The coin the reserve is held in, when there is one.
  final AssetId? feeAsset;

  @override
  List<Object?> get props => [amount, reservedForFees, feeAsset];
}

/// Where a swap has got to, in terms a user interface can render directly.
///
/// The wire states collapse into the moments a user actually distinguishes.
/// [RoutedSwapProgress.rawState] keeps the original for logs.
enum RoutedSwapPhase {
  /// Pricing and allowance checks. Nothing has been sent.
  preparing,

  /// Sending the exact-amount approval (and a zero-reset first, when the
  /// token requires it). Approval gas is being spent; the sold amount is not.
  approving,

  /// Signing locally. Still stoppable.
  signing,

  /// Handing the transaction to the network. No longer stoppable.
  sending,

  /// Waiting for the source chain to confirm.
  confirming,

  /// Following the bridge to the destination chain.
  bridging,

  /// Finished. Check the outcome — finished is not the same as succeeded.
  finished,

  /// Failed.
  failed,

  /// A phase this build does not recognise.
  unknown,
}

/// What the user ended up with.
class RoutedSwapReceipt with RoutedSwapValue {
  /// Creates a receipt for a finished swap.
  const RoutedSwapReceipt({
    required this.outcome,
    required this.amount,
    this.partialReason,
    this.assetId,
    this.symbol,
  });

  /// Whether the swap completed, partially filled, or refunded.
  final rpc.RoutedSwapOutcome outcome;

  /// Why the outcome is partial, when it is.
  final rpc.RoutedSwapPartialReason? partialReason;

  /// How much was received.
  final Decimal amount;

  /// The received asset, when it maps to a wallet asset.
  final AssetId? assetId;

  /// The provider's symbol, when it does not. Display-only.
  final String? symbol;

  /// Whether this may be presented as a completed swap.
  ///
  /// False for a partial fill and for a refund. Both mean the user did not get
  /// what they asked for and must be surfaced as such, not as a success.
  bool get isSuccess => outcome.isSuccess;

  /// A label for the received token.
  String get tokenLabel => assetId?.id ?? symbol ?? '';

  @override
  List<Object?> get props => [outcome, partialReason, amount, assetId, symbol];
}

/// Failure categories, mapped from the wire `error_type`.
enum RoutedSwapFailureKind {
  /// The fresh quote fell below the accepted minimum. Nothing was sent.
  priceMoved,

  /// Not enough balance, including gas.
  insufficientBalance,

  /// The approval failed. Nothing was swapped.
  approvalFailed,

  /// The source transaction reverted, or did not confirm in time.
  swapTransactionFailed,

  /// An external wallet did not sign. Unreachable for local-key coins.
  signingRejected,

  /// The bridge failed without resolving a refund. Needs the explorer link.
  bridgeFailed,

  /// A pre-sign safety check rejected the route. Nothing was sent.
  preflightRejected,

  /// The internal fresh quote failed: no route, rate limited, provider error,
  /// or amount out of bounds. Nothing was sent.
  quoteUnavailable,

  /// KDF restarted before broadcasting. Nothing executed.
  abortedOnRestart,

  /// The user cancelled before anything was broadcast.
  cancelled,

  /// An internal or transport failure.
  internalError,

  /// Something else, including variants newer than this build.
  unknown,
}

/// Whether, and how, the sold funds moved.
enum RoutedSwapFundsMovement {
  /// Nothing was broadcast. The balance is unchanged.
  none,

  /// Only network fees were spent — on an approval, or on a swap transaction
  /// that reverted. The sold amount never left.
  feesOnly,

  /// The swap transaction may have gone out. Never tell the user the funds
  /// did not move.
  uncertain,

  /// The sold amount left the source chain.
  sent,
}

/// What a user can sensibly do after a failure.
enum RoutedSwapRetryPolicy {
  /// Starting the same swap again is reasonable.
  retry,

  /// Price again first: the route, amount or price must change.
  requote,

  /// Fix something outside the swap (usually balance) before trying again.
  fixAndRetry,

  /// Wait: the outcome is not settled yet.
  wait,

  /// Do not retry; hand the evidence to support.
  contactSupport,
}

/// Why a swap failed, and whether the user's funds moved.
class RoutedSwapFailure with RoutedSwapValue {
  /// Creates a failure description.
  const RoutedSwapFailure({
    required this.kind,
    required this.errorType,
    required this.message,
    required this.fundsMovement,
    required this.retryPolicy,
    this.details = const {},
    this.freshOffer,
    this.approvalFailureReason,
    this.txFailureReason,
    this.signingRejectionReason,
    this.preflightCheck,
    this.shortfall,
    this.bounds,
    this.noRouteReasons = const [],
    this.providerRequestId,
    this.sourceTxHash,
    this.providerExplorerUrl,
  });

  /// The failure category.
  final RoutedSwapFailureKind kind;

  /// The raw wire `error_type`, for logs and support.
  final String errorType;

  /// KDF's human-readable explanation. Diagnostic; not localized.
  final String message;

  /// Whether the sold funds moved.
  final RoutedSwapFundsMovement fundsMovement;

  /// What to offer next.
  final RoutedSwapRetryPolicy retryPolicy;

  /// The raw `error_data` payload.
  final Map<String, dynamic> details;

  /// For [RoutedSwapFailureKind.priceMoved], the re-priced offer, ready to
  /// accept. Lets a "price changed" prompt retry in one tap.
  final RoutedSwapOffer? freshOffer;

  /// For [RoutedSwapFailureKind.approvalFailed].
  final rpc.RoutedSwapApprovalFailureReason? approvalFailureReason;

  /// For [RoutedSwapFailureKind.swapTransactionFailed].
  final rpc.RoutedSwapTxFailureReason? txFailureReason;

  /// For [RoutedSwapFailureKind.signingRejected].
  final rpc.RoutedSwapSigningRejectionReason? signingRejectionReason;

  /// For [RoutedSwapFailureKind.preflightRejected].
  final rpc.RoutedSwapPreflightCheck? preflightCheck;

  /// For [RoutedSwapFailureKind.insufficientBalance].
  final RoutedSwapShortfall? shortfall;

  /// For an out-of-bounds amount.
  final RoutedSwapAmountBounds? bounds;

  /// For a missing route: display strings with no stable format.
  final List<String> noRouteReasons;

  /// The provider's support-correlation id, on provider-originated errors.
  final String? providerRequestId;

  /// The source transaction, when the failure reports one.
  final String? sourceTxHash;

  /// Provider explorer link, when the failure reports one.
  final String? providerExplorerUrl;

  /// Whether nothing was broadcast, so the user's balance is unchanged.
  bool get fundsUntouched => fundsMovement == RoutedSwapFundsMovement.none;

  /// Whether starting the same swap again is a sensible thing to offer.
  bool get isRetryable =>
      retryPolicy == RoutedSwapRetryPolicy.retry ||
      retryPolicy == RoutedSwapRetryPolicy.requote;

  @override
  List<Object?> get props => [
    kind,
    errorType,
    message,
    fundsMovement,
    retryPolicy,
    details,
    freshOffer,
    approvalFailureReason,
    txFailureReason,
    signingRejectionReason,
    preflightCheck,
    shortfall,
    bounds,
    noRouteReasons,
    providerRequestId,
    sourceTxHash,
    providerExplorerUrl,
  ];
}

/// How much of a coin was missing.
class RoutedSwapShortfall with RoutedSwapValue {
  /// Creates a shortfall.
  const RoutedSwapShortfall({
    required this.ticker,
    required this.available,
    required this.required,
    this.assetId,
  });

  /// The coin that ran short.
  final String ticker;

  /// The wallet asset, when the ticker maps to one.
  final AssetId? assetId;

  /// What was available.
  final Decimal available;

  /// What was required.
  final Decimal required;

  @override
  List<Object?> get props => [ticker, assetId, available, required];
}

/// The accepted range for an amount.
class RoutedSwapAmountBounds with RoutedSwapValue {
  /// Creates bounds.
  const RoutedSwapAmountBounds({required this.min, required this.max});

  /// Lower bound, when parseable.
  final Decimal? min;

  /// Upper bound, when parseable.
  final Decimal? max;

  @override
  List<Object?> get props => [min, max];
}

/// The request side accepted at `init`, from the durable record.
class RoutedSwapRequest with RoutedSwapValue {
  /// Creates the requested side.
  const RoutedSwapRequest({
    required this.fromTicker,
    required this.toTicker,
    required this.amount,
    this.from,
    this.to,
  });

  /// Source ticker.
  final String fromTicker;

  /// Destination ticker.
  final String toTicker;

  /// Source asset, when the ticker maps to one.
  final AssetId? from;

  /// Destination asset, when the ticker maps to one.
  final AssetId? to;

  /// Requested sell amount. What was asked for — not proof anything moved.
  final Decimal amount;

  @override
  List<Object?> get props => [fromTicker, toTicker, from, to, amount];
}

/// Actual gas paid by one transaction.
class RoutedSwapGasPaid with RoutedSwapValue {
  /// Creates a gas record.
  const RoutedSwapGasPaid({
    required this.ticker,
    required this.amount,
    this.txHash,
    this.assetId,
  });

  /// The transaction that paid it, when itemised.
  final String? txHash;

  /// The native coin it was paid in.
  final String ticker;

  /// The wallet asset, when the ticker maps to one.
  final AssetId? assetId;

  /// How much.
  final Decimal amount;

  @override
  List<Object?> get props => [txHash, ticker, assetId, amount];
}

/// A snapshot of a routed swap.
///
/// The same type describes a live swap and one recovered from history, so
/// nothing downstream has to branch on where the data came from. Fields only
/// the durable record carries ([createdAt], [requested], [gasSpent], …) are
/// filled whenever a history read has been made for the swap.
class RoutedSwapProgress with RoutedSwapValue {
  /// Creates a swap snapshot.
  const RoutedSwapProgress({
    required this.uuid,
    required this.phase,
    required this.canCancel,
    this.provider,
    this.rawState,
    this.bridgeStage,
    this.acceptedOffer,
    this.executedOffer,
    this.receipt,
    this.failure,
    this.approvalTxHashes = const [],
    this.sourceTxHash,
    this.destinationTxHash,
    this.explorerUrl,
    this.providerStatusDetail,
    this.estimatedDuration,
    this.actionUrl,
    this.createdAt,
    this.updatedAt,
    this.finishedAt,
    this.requested,
    this.minToAmountAccepted,
    this.gasSpent = const [],
    this.totalGasSpent = const [],
    this.delayedSince,
  });

  /// The durable swap id. Valid across restarts.
  final String uuid;

  /// Where the swap has got to.
  final RoutedSwapPhase phase;

  /// Whether cancelling would currently be accepted.
  final bool canCancel;

  /// Echoed provider. Diagnostic.
  final String? provider;

  /// The wire state string, for logs and support escalation.
  final String? rawState;

  /// While bridging: the KDF-owned stage that drives display.
  final rpc.RoutedSwapBridgeStage? bridgeStage;

  /// The offer the user accepted, for a swap started in this session.
  final RoutedSwapOffer? acceptedOffer;

  /// The route actually being executed, once the engine has priced it. May
  /// differ from [acceptedOffer].
  final RoutedSwapOffer? executedOffer;

  /// Set once the swap finishes with a terminal `Ok`.
  final RoutedSwapReceipt? receipt;

  /// Set once the swap fails.
  final RoutedSwapFailure? failure;

  /// Every approval transaction observed, in order. A zero-reset produces two.
  final List<String> approvalTxHashes;

  /// The source-chain transaction.
  final String? sourceTxHash;

  /// The destination-chain transaction.
  final String? destinationTxHash;

  /// A provider explorer link for the route.
  final String? explorerUrl;

  /// Opaque provider progress text.
  ///
  /// In the provider's own language and subject to change without notice.
  /// Suitable for a details disclosure, not for primary copy.
  final String? providerStatusDetail;

  /// Provider estimate for the route.
  final Duration? estimatedDuration;

  /// Where the user must act, when the bridge stage requires it.
  final String? actionUrl;

  /// When the swap was started. Immutable.
  final DateTime? createdAt;

  /// When the durable record last changed.
  final DateTime? updatedAt;

  /// When the swap reached a terminal state.
  final DateTime? finishedAt;

  /// The request side accepted at `init`.
  final RoutedSwapRequest? requested;

  /// The guaranteed minimum accepted at `init`.
  final Decimal? minToAmountAccepted;

  /// Actual gas paid per transaction.
  final List<RoutedSwapGasPaid> gasSpent;

  /// Actual gas paid per native coin.
  final List<RoutedSwapGasPaid> totalGasSpent;

  /// Set while status reads are failing: the last good snapshot is being
  /// shown and may be out of date. A delay is not a failure.
  final DateTime? delayedSince;

  /// Whether the swap has stopped, either way.
  bool get isTerminal =>
      phase == RoutedSwapPhase.finished || phase == RoutedSwapPhase.failed;

  /// Whether the swap finished and delivered what was asked for.
  ///
  /// A partial fill and a refund are both terminal and neither is a success.
  bool get isSuccess => receipt?.isSuccess ?? false;

  /// The most recent approval transaction, when there is one.
  String? get approvalTxHash =>
      approvalTxHashes.isEmpty ? null : approvalTxHashes.last;

  /// The offer that best describes the swap: the executed route once known,
  /// otherwise the accepted one.
  RoutedSwapOffer? get offer => executedOffer ?? acceptedOffer;

  /// A copy with the given fields replaced.
  RoutedSwapProgress copyWith({
    RoutedSwapOffer? acceptedOffer,
    List<String>? approvalTxHashes,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? finishedAt,
    RoutedSwapRequest? requested,
    Decimal? minToAmountAccepted,
    List<RoutedSwapGasPaid>? gasSpent,
    List<RoutedSwapGasPaid>? totalGasSpent,
    DateTime? delayedSince,
    bool clearDelayedSince = false,
  }) => RoutedSwapProgress(
    uuid: uuid,
    phase: phase,
    canCancel: canCancel,
    provider: provider,
    rawState: rawState,
    bridgeStage: bridgeStage,
    acceptedOffer: acceptedOffer ?? this.acceptedOffer,
    executedOffer: executedOffer,
    receipt: receipt,
    failure: failure,
    approvalTxHashes: approvalTxHashes ?? this.approvalTxHashes,
    sourceTxHash: sourceTxHash,
    destinationTxHash: destinationTxHash,
    explorerUrl: explorerUrl,
    providerStatusDetail: providerStatusDetail,
    estimatedDuration: estimatedDuration,
    actionUrl: actionUrl,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    finishedAt: finishedAt ?? this.finishedAt,
    requested: requested ?? this.requested,
    minToAmountAccepted: minToAmountAccepted ?? this.minToAmountAccepted,
    gasSpent: gasSpent ?? this.gasSpent,
    totalGasSpent: totalGasSpent ?? this.totalGasSpent,
    delayedSince: clearDelayedSince
        ? null
        : (delayedSince ?? this.delayedSince),
  );

  @override
  List<Object?> get props => [
    uuid,
    phase,
    canCancel,
    provider,
    rawState,
    bridgeStage,
    acceptedOffer,
    executedOffer,
    receipt,
    failure,
    approvalTxHashes,
    sourceTxHash,
    destinationTxHash,
    explorerUrl,
    providerStatusDetail,
    estimatedDuration,
    actionUrl,
    createdAt,
    updatedAt,
    finishedAt,
    requested,
    minToAmountAccepted,
    gasSpent,
    totalGasSpent,
    delayedSince,
  ];
}

/// A page of routed swaps from the durable record.
class RoutedSwapHistoryPage with RoutedSwapValue {
  /// Creates a page.
  const RoutedSwapHistoryPage({
    required this.entries,
    required this.total,
    required this.pageNumber,
    required this.totalPages,
  });

  /// The swaps on this page, newest first.
  final List<RoutedSwapProgress> entries;

  /// Matching swaps across all pages.
  final int total;

  /// This page's 1-based number.
  final int pageNumber;

  /// How many pages match.
  final int totalPages;

  /// Whether a later page exists.
  bool get hasMore => pageNumber < totalPages;

  @override
  List<Object?> get props => [entries, total, pageNumber, totalPages];
}

/// Why a cancel was refused.
enum RoutedSwapCancelRefusal {
  /// The transaction has already been handed to the network. Tracking
  /// continues.
  alreadyBroadcast,

  /// The swap has already ended.
  alreadyFinished,

  /// The swap is only known from the durable record — its task is gone, so
  /// there is nothing addressable to cancel.
  notAddressable,
}

/// Thrown when a swap can no longer be cancelled.
///
/// Cancellation stops being possible the moment KDF hands the transaction to
/// the network, which is a race the caller cannot win by checking first.
class RoutedSwapNotCancellableException implements Exception {
  /// Creates the exception for the swap identified by [uuid].
  const RoutedSwapNotCancellableException(
    this.uuid,
    this.phase, {
    this.refusal = RoutedSwapCancelRefusal.alreadyBroadcast,
  });

  /// The swap that could not be cancelled.
  final String uuid;

  /// The phase it had reached.
  final RoutedSwapPhase phase;

  /// Why.
  final RoutedSwapCancelRefusal refusal;

  @override
  String toString() =>
      'Routed swap $uuid cannot be cancelled (${refusal.name}, '
      'phase ${phase.name}).';
}

/// Thrown when a cancel request's outcome could not be confirmed.
///
/// The swap may or may not have been cancelled; its progress stream keeps
/// reporting the truth.
class RoutedSwapCancelUnconfirmedException implements Exception {
  /// Creates the exception for [uuid].
  const RoutedSwapCancelUnconfirmedException(this.uuid, this.cause);

  /// The swap.
  final String uuid;

  /// What went wrong.
  final Object cause;

  @override
  String toString() => 'Could not confirm cancelling routed swap $uuid.';
}

/// Thrown when `start` could not confirm whether the swap began.
///
/// The engine may already be running it. Re-arming a start button on this is
/// how one tap becomes two real swaps — check history instead.
class RoutedSwapStartUnconfirmedException implements Exception {
  /// Creates the exception.
  const RoutedSwapStartUnconfirmedException(this.cause, {this.taskId});

  /// What went wrong.
  final Object cause;

  /// The task id, when `init` answered before the failure.
  final int? taskId;

  @override
  String toString() => 'Could not confirm whether the routed swap started.';
}

/// Thrown when a swap cannot be found, live or in history.
class RoutedSwapNotFoundException implements Exception {
  /// Creates the exception for [uuid].
  const RoutedSwapNotFoundException(this.uuid);

  /// The swap that could not be resolved.
  final String uuid;

  @override
  String toString() => 'No routed swap found for $uuid.';
}
