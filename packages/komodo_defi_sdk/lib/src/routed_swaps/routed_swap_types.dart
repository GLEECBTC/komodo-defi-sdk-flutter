import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;
import 'package:komodo_defi_sdk/src/routed_swaps/routed_swap_value.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

part 'routed_swap_outcome_types.dart';
part 'routed_swap_progress.dart';

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
