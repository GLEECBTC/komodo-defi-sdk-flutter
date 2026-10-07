part of 'routed_swap_types.dart';

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

  /// The provider's symbol, or KDF's ticker the wallet cannot resolve, when
  /// it does not. Display-only.
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
