import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// What a routed swap will cost, as one list rather than two.
///
/// The wire contract splits costs into `fee_costs` (provider/protocol) and
/// `gas_costs` (chain), each with its own inclusion rules, and leaves approval
/// gas out of both. Reconciling that correctly is easy to get wrong and the
/// mistake is a wrong number in front of a user, so the SDK does it once here.
class RoutedSwapCost {
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

  /// Human-readable label from the provider.
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

  /// USD value, when the provider supplied one.
  final Decimal? usdValue;

  /// A label for the token this cost is paid in.
  String get tokenLabel => assetId?.id ?? symbol ?? '';
}

/// The kind of a [RoutedSwapCost].
enum RoutedSwapCostKind {
  /// Charged by the aggregator or a protocol along the route.
  providerFee,

  /// Chain gas for the swap transaction itself.
  gas,
}

/// A priced route that is ready to execute.
///
/// Carries its own execution guard, so starting a swap never requires the
/// caller to re-derive `min_to_amount`. Passing the *expected* receive as the
/// guard instead of the guaranteed minimum would reject nearly every swap, and
/// that footgun is removed by construction: `RoutedSwapManager.start` takes an
/// offer, not loose numbers.
class RoutedSwapOffer {
  /// Wraps a parsed route with the context needed to execute and display it.
  const RoutedSwapOffer({
    required this.from,
    required this.to,
    required this.sellAmount,
    required this.expectedReceive,
    required this.guaranteedReceive,
    required this.toolName,
    required this.isCrossChain,
    required this.costs,
    required this.quotedAt,
    required this.mayRequireApproval,
    required this.provider,
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

  /// Display name of the executing bridge or exchange.
  final String toolName;

  /// Logo for [toolName], when the provider supplied one.
  final String? toolLogoUrl;

  /// Whether the route crosses chains, and therefore has a bridge wait that
  /// can run to tens of minutes.
  final bool isCrossChain;

  /// Provider fees and gas, already reconciled.
  final List<RoutedSwapCost> costs;

  /// Provider estimate for the whole route.
  final Duration? estimatedDuration;

  /// When this offer was priced.
  final DateTime quotedAt;

  /// Whether executing may additionally require one or two ERC-20 approval
  /// transactions whose gas is **not** included in [costs].
  ///
  /// Derived from the sell asset's protocol rather than from the quote, which
  /// does not report it. When true, any total built from [costs] is a floor,
  /// and the UI must say so.
  final bool mayRequireApproval;

  /// The aggregator that priced this route.
  final String provider;

  /// The slippage tolerance this offer was priced at.
  final double? slippage;

  /// The raw route, kept so execution reproduces exactly what was shown.
  RoutedSwapOffer copyWith({DateTime? quotedAt}) => RoutedSwapOffer(
    from: from,
    to: to,
    sellAmount: sellAmount,
    expectedReceive: expectedReceive,
    guaranteedReceive: guaranteedReceive,
    toolName: toolName,
    toolLogoUrl: toolLogoUrl,
    isCrossChain: isCrossChain,
    costs: costs,
    estimatedDuration: estimatedDuration,
    quotedAt: quotedAt ?? this.quotedAt,
    mayRequireApproval: mayRequireApproval,
    provider: provider,
    slippage: slippage,
  );

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

  /// Total of the costs that are charged on top of the sell amount, per token.
  ///
  /// Costs already deducted from the receive amount are excluded, because
  /// adding them would charge the user twice in the UI.
  Map<String, Decimal> get additionalCostsByToken {
    final totals = <String, Decimal>{};
    for (final cost in costs.where((c) => !c.isDeductedFromReceive)) {
      totals[cost.tokenLabel] =
          (totals[cost.tokenLabel] ?? Decimal.zero) + cost.amount;
    }
    return totals;
  }
}

/// Where a swap has got to, in terms a user interface can render directly.
///
/// The seven wire states collapse into the moments a user actually
/// distinguishes. [RoutedSwapProgress.rawState] keeps the original for logs.
enum RoutedSwapPhase {
  /// Pricing and allowance checks. Nothing has been sent.
  preparing,

  /// An ERC-20 approval is on-chain.
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
class RoutedSwapReceipt {
  /// Creates a receipt for a finished swap.
  const RoutedSwapReceipt({
    required this.outcome,
    required this.amount,
    this.assetId,
    this.symbol,
  });

  /// Whether the swap completed, partially filled, or refunded.
  final rpc.RoutedSwapOutcome outcome;

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
}

/// Why a swap failed, and whether the user's funds moved.
class RoutedSwapFailure {
  /// Creates a failure description.
  const RoutedSwapFailure({
    required this.kind,
    required this.message,
    required this.fundsUntouched,
    this.details = const {},
    this.freshOffer,
  });

  /// The failure category.
  final RoutedSwapFailureKind kind;

  /// KDF's human-readable explanation.
  final String message;

  /// Whether nothing was broadcast, so the user's balance is unchanged apart
  /// from any approval gas.
  ///
  /// Conservative: false whenever this build cannot prove otherwise. Telling
  /// someone their money is safe when it might not be is the one error worth
  /// avoiding absolutely.
  final bool fundsUntouched;

  /// The raw `error_data` payload.
  final Map<String, dynamic> details;

  /// For [RoutedSwapFailureKind.priceMoved], the re-priced offer, ready to
  /// accept. Lets a "price changed" prompt retry in one tap.
  final RoutedSwapOffer? freshOffer;

  /// Whether starting the same swap again is a sensible thing to offer.
  bool get isRetryable => switch (kind) {
    RoutedSwapFailureKind.priceMoved ||
    RoutedSwapFailureKind.insufficientBalance ||
    RoutedSwapFailureKind.abortedOnRestart ||
    RoutedSwapFailureKind.cancelled => true,
    _ => false,
  };
}

/// Failure categories, mapped from the wire `error_type`.
enum RoutedSwapFailureKind {
  /// The fresh quote fell below the accepted minimum. Nothing was sent.
  priceMoved,

  /// Not enough balance, including gas.
  insufficientBalance,

  /// The ERC-20 approval failed. Nothing was swapped.
  approvalFailed,

  /// The source transaction reverted.
  swapTransactionFailed,

  /// The bridge failed without resolving a refund. Needs the explorer link.
  bridgeFailed,

  /// KDF restarted before broadcasting. Nothing executed.
  abortedOnRestart,

  /// The user cancelled before anything was broadcast.
  cancelled,

  /// Something else, including variants newer than this build.
  unknown,
}

/// A snapshot of a routed swap.
///
/// The same type describes a live swap and one recovered from history, so
/// nothing downstream has to branch on where the data came from.
class RoutedSwapProgress {
  /// Creates a swap snapshot.
  const RoutedSwapProgress({
    required this.uuid,
    required this.phase,
    required this.canCancel,
    this.rawState,
    this.receipt,
    this.failure,
    this.approvalTxHash,
    this.sourceTxHash,
    this.destinationTxHash,
    this.explorerUrl,
    this.providerStatusDetail,
    this.estimatedDuration,
  });

  /// The durable swap id. Valid across restarts.
  final String uuid;

  /// Where the swap has got to.
  final RoutedSwapPhase phase;

  /// Whether cancelling would currently be accepted.
  final bool canCancel;

  /// The wire state string, for logs and support escalation.
  final String? rawState;

  /// Set once the swap finishes successfully.
  final RoutedSwapReceipt? receipt;

  /// Set once the swap fails.
  final RoutedSwapFailure? failure;

  /// The approval transaction, when one was sent.
  final String? approvalTxHash;

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

  /// Whether the swap has stopped, either way.
  bool get isTerminal =>
      phase == RoutedSwapPhase.finished || phase == RoutedSwapPhase.failed;

  /// Whether the swap finished and delivered what was asked for.
  ///
  /// A partial fill and a refund are both terminal and neither is a success.
  bool get isSuccess => receipt?.isSuccess ?? false;
}

/// Thrown when a swap can no longer be cancelled.
///
/// Cancellation stops being possible the moment KDF hands the transaction to
/// the network, which is a race the caller cannot win by checking first.
class RoutedSwapNotCancellableException implements Exception {
  /// Creates the exception for the swap identified by [uuid].
  const RoutedSwapNotCancellableException(this.uuid, this.phase);

  /// The swap that could not be cancelled.
  final String uuid;

  /// The phase it had reached.
  final RoutedSwapPhase phase;

  @override
  String toString() =>
      'Routed swap $uuid can no longer be cancelled (phase: ${phase.name}). '
      'The transaction has already been handed to the network.';
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
