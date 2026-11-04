part of 'routed_swap_fixture.dart';

/// The in-progress states of `task::routed_swap::status`, in engine order.
enum RoutedSwapRunState {
  /// The internal fresh quote.
  fetchingQuote('FetchingQuote'),

  /// Static preflight, balances and the confirmed allowance.
  checkingAllowance('CheckingAllowance'),

  /// ERC-20 approval transactions.
  approving('Approving'),

  /// Signing. The last cancellable state.
  signing('Signing'),

  /// The irreversible handoff; cancellation is refused from here on.
  broadcasting('Broadcasting'),

  /// Source-chain confirmation.
  waitingSourceConfirmation('WaitingSourceConfirmation'),

  /// Cross-chain only: following the bridge.
  trackingBridge('TrackingBridge');

  const RoutedSwapRunState(this.wire);

  /// The `state` string on the wire.
  final String wire;

  /// Whether the engine's cancellation gate is irreversible in this state.
  bool get isPostBroadcast => index >= RoutedSwapRunState.broadcasting.index;
}

/// One persisted in-progress transition of a [RoutedSwapRun].
class RoutedSwapTick {
  const RoutedSwapTick._(
    this.state, {
    this.approveTxHash,
    this.withSourceTxHash = true,
    this.substatus,
    this.substatusMessage,
    this.providerExplorerUrl,
  });

  /// `Approving`: without [txHash] until the approval is broadcast, then with
  /// the hash just broadcast — a zero-reset shows two different hashes.
  const RoutedSwapTick.approving([String? txHash])
    : this._(RoutedSwapRunState.approving, approveTxHash: txHash);

  /// `Broadcasting`. With an external wallet that broadcasts itself the hash
  /// is unknown until the wallet answers, so [withSourceTxHash] is false.
  const RoutedSwapTick.broadcasting({bool withSourceTxHash = true})
    : this._(
        RoutedSwapRunState.broadcasting,
        withSourceTxHash: withSourceTxHash,
      );

  /// `TrackingBridge` after one provider status poll. The KDF-owned `stage`
  /// is derived from [substatus] the way the engine derives it:
  /// `WAIT_SOURCE_CONFIRMATIONS` → `bridging`, `WAIT_DESTINATION_TRANSACTION`
  /// → `destination_pending`, `REFUND_IN_PROGRESS` → `refund_pending`
  /// (which latches), anything else leaves it where it was. The first
  /// `TrackingBridge` of a run is persisted before the provider reports
  /// anything, so it carries none of these.
  const RoutedSwapTick.trackingBridge({
    String? substatus,
    String? substatusMessage,
    String? providerExplorerUrl,
  }) : this._(
         RoutedSwapRunState.trackingBridge,
         substatus: substatus,
         substatusMessage: substatusMessage,
         providerExplorerUrl: providerExplorerUrl,
       );

  /// `FetchingQuote`, persisted at `init`.
  static const RoutedSwapTick fetchingQuote = RoutedSwapTick._(
    RoutedSwapRunState.fetchingQuote,
  );

  /// `CheckingAllowance`.
  static const RoutedSwapTick checkingAllowance = RoutedSwapTick._(
    RoutedSwapRunState.checkingAllowance,
  );

  /// `Signing`.
  static const RoutedSwapTick signing = RoutedSwapTick._(
    RoutedSwapRunState.signing,
  );

  /// `WaitingSourceConfirmation`.
  static const RoutedSwapTick waitingSourceConfirmation = RoutedSwapTick._(
    RoutedSwapRunState.waitingSourceConfirmation,
  );

  /// The state.
  final RoutedSwapRunState state;

  /// The approval hash on an `Approving` tick.
  final String? approveTxHash;

  /// Whether a `Broadcasting` tick already knows the source hash.
  final bool withSourceTxHash;

  /// The provider's opaque substatus.
  final String? substatus;

  /// The provider's opaque substatus message.
  final String? substatusMessage;

  /// The provider's explorer link.
  final String? providerExplorerUrl;
}

/// The terminal `Ok` outcomes.
enum RoutedSwapRunOutcome {
  /// The requested coin at or above the accepted minimum.
  completed('completed'),

  /// Delivered on the destination chain, below the minimum or as another
  /// token.
  partial('partial'),

  /// Funds returned on the source chain.
  refunded('refunded');

  const RoutedSwapRunOutcome(this.wire);

  /// The `outcome` string on the wire.
  final String wire;
}

/// A scripted `routed_swap::quote` route, and the shape of `executed_route`
/// and `fresh_route`.
class RoutedSwapQuote {
  /// Creates a route. [amount] is the sold amount; leave it null to echo the
  /// requested amount, as the engine does.
  RoutedSwapQuote({
    required this.from,
    required this.to,
    required this.toAmount,
    required this.toAmountMin,
    this.amount,
    this.crossChain = true,
    this.toolKey = 'stargateV2',
    this.toolName = 'Stargate V2',
    this.toolLogoUrl,
    this.fromAddress = RoutedSwapQuote.defaultAddress,
    this.approval,
    this.steps = const [],
    this.feeCosts = const [],
    this.gasCosts = const [],
    this.executionDurationS = 95,
  }) {
    if (_decimal(toAmountMin, 'toAmountMin') > _decimal(toAmount, 'toAmount')) {
      throw ArgumentError(
        'toAmountMin ($toAmountMin) exceeds toAmount ($toAmount): the engine '
        'rejects that route in preflight (amount_bounds).',
      );
    }
    if (amount != null) _decimal(amount!, 'amount');
    if (executionDurationS < 0) {
      throw ArgumentError.value(executionDurationS, 'executionDurationS');
    }
  }

  /// The wallet address routes send from and to by default.
  static const String defaultAddress =
      '0x5520086ad0cd4e4a4fa0d4c3e0a7c4c1b0b1c0de';

  /// Source ticker.
  final String from;

  /// Destination ticker.
  final String to;

  /// Sold amount, or null to echo the request.
  final String? amount;

  /// Expected receive.
  final String toAmount;

  /// Guaranteed receive after slippage.
  final String toAmountMin;

  /// `cross_chain` when true, `same_chain` otherwise.
  final bool crossChain;

  /// Stable provider tool key.
  final String toolKey;

  /// Tool name.
  final String toolName;

  /// Tool logo; omitted when null.
  final String? toolLogoUrl;

  /// The source coin's enabled address. `to_address` always equals it in v1.
  final String fromAddress;

  /// Approval transactions the sell needs, or null when none.
  final RoutedSwapQuoteApproval? approval;

  /// Route legs.
  final List<RoutedSwapQuoteStep> steps;

  /// Provider and protocol fees.
  final List<RoutedSwapQuoteFee> feeCosts;

  /// Execution gas.
  final List<RoutedSwapQuoteGas> gasCosts;

  /// Estimated duration, seconds.
  final int executionDurationS;

  /// Per-coin sums of [gasCosts] plus the approval gas, in first-seen order
  /// (`add_gas_total`). A total carries `amount_usd` only when every row it
  /// sums does; approval gas never does.
  List<Map<String, dynamic>> get totalGasCosts {
    final amounts = <String, Decimal>{};
    final usd = <String, Decimal?>{};
    void add(String coin, String amount, String? amountUsd) {
      final value = Decimal.parse(amount);
      final valueUsd = amountUsd == null ? null : Decimal.parse(amountUsd);
      if (!amounts.containsKey(coin)) {
        amounts[coin] = value;
        usd[coin] = valueUsd;
        return;
      }
      amounts[coin] = amounts[coin]! + value;
      final sum = usd[coin];
      usd[coin] = sum == null || valueUsd == null ? null : sum + valueUsd;
    }

    for (final gas in gasCosts) {
      add(gas.coin, gas.amount, gas.amountUsd);
    }
    final approval = this.approval;
    if (approval != null) add(approval.gasCoin, approval.gasAmount, null);
    return [
      for (final coin in amounts.keys)
        {
          'coin': coin,
          'amount': amounts[coin].toString(),
          if (usd[coin] != null) 'amount_usd': usd[coin].toString(),
        },
    ];
  }

  /// The `RoutedSwapRoute` wire object, selling [amount] (or this route's
  /// own amount).
  Map<String, dynamic> toJson({String? amount}) {
    final sold = this.amount ?? amount;
    if (sold == null) {
      throw ArgumentError('A route with no amount needs the requested one.');
    }
    return {
      'provider': _provider,
      'from': {'coin': from, 'amount': sold},
      'to': {'coin': to, 'amount': toAmount, 'amount_min': toAmountMin},
      'tool': {
        'key': toolKey,
        'name': toolName,
        if (toolLogoUrl != null) 'logo_url': toolLogoUrl,
      },
      'kind': crossChain ? 'cross_chain' : 'same_chain',
      'from_address': fromAddress,
      'to_address': fromAddress,
      if (approval != null) 'approval': approval!.toJson(),
      'total_gas_costs': totalGasCosts,
      'steps': [for (final step in steps) step.toJson()],
      'fee_costs': [for (final fee in feeCosts) fee.toJson()],
      'gas_costs': [for (final gas in gasCosts) gas.toJson()],
      'execution_duration_s': executionDurationS,
    };
  }
}

/// The approval transactions a sell needs before the swap.
class RoutedSwapQuoteApproval {
  /// One exact-amount approval (`no_allowance`).
  const RoutedSwapQuoteApproval.noAllowance({
    required this.gasCoin,
    required this.gasAmount,
    this.spender = RoutedSwapQuoteApproval.lifiDiamond,
  }) : resetsFirst = false;

  /// A reset to zero, then the exact-amount approval (`zero_reset`).
  const RoutedSwapQuoteApproval.zeroReset({
    required this.gasCoin,
    required this.gasAmount,
    this.spender = RoutedSwapQuoteApproval.lifiDiamond,
  }) : resetsFirst = true;

  /// LI.FI's diamond, the spender KDF allowlists.
  static const String lifiDiamond =
      '0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE';

  /// The coin paying approval gas: the source chain's native coin.
  final String gasCoin;

  /// Estimated approval gas for all of the approval transactions.
  final String gasAmount;

  /// The contract the approval grants to.
  final String spender;

  /// Whether the allowance is reset to zero first.
  final bool resetsFirst;

  /// The `approval` wire object. Its single gas row never has USD.
  Map<String, dynamic> toJson() => {
    'required': true,
    'tx_count': resetsFirst ? 2 : 1,
    'reason': resetsFirst ? 'zero_reset' : 'no_allowance',
    'spender': spender,
    'gas_costs': [
      {'coin': gasCoin, 'amount': gasAmount},
    ],
  };
}

/// One route leg.
class RoutedSwapQuoteStep {
  /// A conversion on one chain.
  const RoutedSwapQuoteStep.swap({required this.tool, required int chainId})
    : _chainId = chainId,
      _fromChainId = null,
      _toChainId = null;

  /// A bridge between two chains.
  const RoutedSwapQuoteStep.cross({
    required this.tool,
    required int fromChainId,
    required int toChainId,
  }) : _chainId = null,
       _fromChainId = fromChainId,
       _toChainId = toChainId;

  /// Provider tool key.
  final String tool;
  final int? _chainId;
  final int? _fromChainId;
  final int? _toChainId;

  /// The tagged `steps[]` wire object.
  Map<String, dynamic> toJson() => _chainId != null
      ? {'type': 'swap', 'tool': tool, 'chain_id': _chainId}
      : {
          'type': 'cross',
          'tool': tool,
          'from_chain_id': _fromChainId,
          'to_chain_id': _toChainId,
        };
}

/// One provider or protocol fee.
class RoutedSwapQuoteFee {
  /// Creates a fee in a KDF [coin] or, when the token maps to none, a
  /// provider [symbol] — exactly one of the two.
  RoutedSwapQuoteFee({
    required this.name,
    required this.amount,
    required this.included,
    this.coin,
    this.symbol,
    this.amountUsd,
  }) {
    if ((coin == null) == (symbol == null)) {
      throw ArgumentError('A fee names exactly one of coin or symbol.');
    }
  }

  /// Provider label.
  final String name;

  /// Fee amount.
  final String amount;

  /// Whether it is already deducted from `to.amount`.
  final bool included;

  /// KDF ticker.
  final String? coin;

  /// Provider symbol.
  final String? symbol;

  /// Provider USD value.
  final String? amountUsd;

  /// The `fee_costs[]` wire object.
  Map<String, dynamic> toJson() => {
    'name': name,
    if (coin != null) 'coin': coin,
    if (symbol != null) 'symbol': symbol,
    'amount': amount,
    if (amountUsd != null) 'amount_usd': amountUsd,
    'included': included,
  };
}

/// Execution gas for one coin.
class RoutedSwapQuoteGas {
  /// Creates a gas row.
  const RoutedSwapQuoteGas({
    required this.coin,
    required this.amount,
    this.amountUsd,
  });

  /// Gas coin ticker.
  final String coin;

  /// Gas amount.
  final String amount;

  /// Provider USD value.
  final String? amountUsd;

  /// The `gas_costs[]` wire object.
  Map<String, dynamic> toJson() => {
    'coin': coin,
    'amount': amount,
    if (amountUsd != null) 'amount_usd': amountUsd,
  };
}
