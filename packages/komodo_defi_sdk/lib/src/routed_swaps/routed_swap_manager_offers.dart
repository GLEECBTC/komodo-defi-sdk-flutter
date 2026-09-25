part of 'routed_swap_manager.dart';

/// Turns engine routes into offers, and finds swaps in the durable record.
extension _RoutedSwapOffers on RoutedSwapManager {
  RoutedSwapHandle _register(_RoutedSwapSession session) {
    final existing = _sessions[session.uuid];
    if (existing != null && !existing.isDisposed) {
      unawaited(session.dispose());
      return _RoutedSwapHandle(existing);
    }
    _sessions[session.uuid] = session;
    session.start();
    return _RoutedSwapHandle(session);
  }

  Future<rpc.RoutedSwapHistoryEntry?> _entryFor(String uuid) async {
    final page = await _client.rpc.routedSwap.history(uuid: uuid, limit: 1);
    return page.entries.isEmpty ? null : page.entries.first;
  }

  /// Finds the record `init` created for [offer] when its task could not be
  /// read back.
  Future<rpc.RoutedSwapHistoryEntry?> _findStartedEntry(
    RoutedSwapOffer offer, {
    required DateTime since,
  }) async {
    try {
      final page = await _client.rpc.routedSwap.history(
        myCoin: offer.from.id,
        otherCoin: offer.to.id,
        fromTimestamp: _unixSeconds(since) - 5,
        limit: 10,
      );
      for (final entry in page.entries) {
        final amount = Decimal.tryParse(entry.requested.amount);
        final minimum = Decimal.tryParse(entry.minToAmountAccepted);
        if (amount == offer.sellAmount &&
            minimum == offer.guaranteedReceive &&
            !_sessions.containsKey(entry.uuid)) {
          return entry;
        }
      }
    } on Object {
      // The caller reports the start as unconfirmed.
    }
    return null;
  }

  Decimal? _decimal(String? value) =>
      value == null ? null : Decimal.tryParse(value);

  RoutedSwapOffer _offerFrom(
    rpc.RoutedSwapRoute route, {
    required AssetId from,
    required AssetId to,
    rpc.RoutedSwapOrder? order,
    double? slippage,
    DateTime? quotedAt,
  }) {
    RoutedSwapCost gasCost(
      rpc.RoutedSwapGasCost gas,
      RoutedSwapCostKind kind,
    ) => RoutedSwapCost(
      label: kind == RoutedSwapCostKind.approvalGas
          ? 'Approval network fee'
          : 'Network fee',
      amount: Decimal.parse(gas.amount.amount),
      kind: kind,
      isDeductedFromReceive: false,
      assetId: gas.amount.coin == null ? null : _resolveAsset(gas.amount.coin!),
      symbol: gas.amount.symbol ?? gas.amount.coin,
      usdValue: _decimal(gas.amountUsd),
    );

    final costs = <RoutedSwapCost>[
      for (final fee in route.feeCosts)
        RoutedSwapCost(
          label: fee.name,
          amount: Decimal.parse(fee.amount.amount),
          kind: RoutedSwapCostKind.providerFee,
          isDeductedFromReceive: fee.included,
          assetId: fee.amount.coin == null
              ? null
              : _resolveAsset(fee.amount.coin!),
          symbol: fee.amount.symbol ?? fee.amount.coin,
          usdValue: _decimal(fee.amountUsd),
        ),
      for (final gas in route.gasCosts) gasCost(gas, RoutedSwapCostKind.gas),
      for (final gas
          in route.approval?.gasCosts ?? const <rpc.RoutedSwapGasCost>[])
        gasCost(gas, RoutedSwapCostKind.approvalGas),
    ];

    final approval = route.approval;
    return RoutedSwapOffer(
      from: from,
      to: to,
      sellAmount: Decimal.parse(route.from.amount),
      expectedReceive: Decimal.parse(route.to.amount),
      guaranteedReceive: Decimal.parse(route.toMinimum.amount),
      kind: route.kind,
      costs: costs,
      networkFees: _networkFeesOf(route),
      legs: [
        for (final step in route.steps)
          RoutedSwapLeg(
            type: step.stepType,
            chainId: step.chainId,
            fromChainId: step.fromChainId,
            toChainId: step.toChainId,
          ),
      ],
      quotedAt: quotedAt ?? DateTime.now(),
      provider: route.provider,
      toolKey: route.tool.key,
      toolName: route.tool.name,
      toolLogoUrl: route.tool.logoUrl,
      route: route,
      order: order,
      fromAddress: route.fromAddress,
      toAddress: route.toAddress,
      approval: approval == null
          ? null
          : RoutedSwapApprovalInfo(
              txCount: approval.txCount,
              resetsFirst: approval.resetsFirst,
              spender: approval.spender,
            ),
      estimatedDuration: route.executionDurationS == null
          ? null
          : Duration(seconds: route.executionDurationS!),
      slippage: slippage,
    );
  }

  /// The per-coin network fee. Uses the engine's totals when present, and
  /// otherwise sums execution and approval gas the same way — a USD value
  /// only when every contributing row has one.
  List<RoutedSwapNetworkFee> _networkFeesOf(rpc.RoutedSwapRoute route) {
    final rows = route.totalGasCosts.isNotEmpty
        ? route.totalGasCosts
        : [...route.gasCosts, ...?route.approval?.gasCosts];
    final amounts = <String, Decimal>{};
    final usd = <String, Decimal?>{};
    for (final row in rows) {
      final ticker = row.amount.label;
      amounts[ticker] =
          (amounts[ticker] ?? Decimal.zero) + Decimal.parse(row.amount.amount);
      final rowUsd = _decimal(row.amountUsd);
      usd[ticker] = !usd.containsKey(ticker)
          ? rowUsd
          : (usd[ticker] == null || rowUsd == null
                ? null
                : usd[ticker]! + rowUsd);
    }
    return [
      for (final entry in amounts.entries)
        RoutedSwapNetworkFee(
          ticker: entry.key,
          assetId: _resolveAsset(entry.key),
          amount: entry.value,
          usdValue: usd[entry.key],
        ),
    ];
  }

  RoutedSwapOffer? _offerFromExecuted(
    rpc.RoutedSwapRoute? route,
    RoutedSwapOffer? accepted, {
    RoutedSwapOffer? previous,
  }) {
    if (route == null) return null;
    // Every poll re-reports the same executed route. Reusing the offer built
    // from it keeps snapshots equal, so an unchanged swap does not re-emit.
    if (previous != null && previous.route == route) return previous;
    final from = accepted?.from ?? _resolveAssetOf(route.from);
    final to = accepted?.to ?? _resolveAssetOf(route.toMinimum);
    if (from == null || to == null) return null;
    return _offerFrom(
      route,
      from: from,
      to: to,
      order: accepted?.order,
      slippage: accepted?.slippage,
      quotedAt: accepted?.quotedAt ?? previous?.quotedAt,
    );
  }

  AssetId? _resolveAssetOf(rpc.RoutedSwapAmount amount) =>
      amount.coin == null ? null : _resolveAsset(amount.coin!);
}
