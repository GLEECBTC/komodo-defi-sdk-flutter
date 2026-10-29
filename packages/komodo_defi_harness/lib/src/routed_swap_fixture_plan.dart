part of 'routed_swap_fixture.dart';

/// A run resolved against its `init` request.
class _Plan {
  _Plan._({
    required this.run,
    required this.uuid,
    required this.from,
    required this.to,
    required this.amount,
    required this.minToAmount,
    required this.route,
    required this.routeJson,
    required this.ladder,
    required this.error,
    required this.sourceTxHash,
    required this.gasCoin,
    required this.okDetails,
  });

  factory _Plan.resolve(
    RoutedSwapRun run, {
    required int seq,
    required String uuid,
    required String from,
    required String to,
    required String amount,
    required String minToAmount,
    required RoutedSwapQuote? displayedRoute,
  }) {
    final route =
        run.route ??
        displayedRoute ??
        RoutedSwapQuote(
          from: from,
          to: to,
          toAmount: minToAmount,
          toAmountMin: minToAmount,
        );
    if (route.from != from || route.to != to) {
      throw ArgumentError(
        'The run executes ${route.from} -> ${route.to} but init asked for '
        '$from -> $to.',
      );
    }
    if (route.amount != null && !_sameNumber(route.amount!, amount)) {
      throw ArgumentError(
        'The run executes ${route.amount} but init sells $amount; the engine '
        'rejects a provider route for a different source amount.',
      );
    }
    final guard = Decimal.parse(minToAmount);
    if (guard <= Decimal.zero || Decimal.parse(amount) <= Decimal.zero) {
      throw ArgumentError(
        'The engine rejects a non-positive amount or min_to_amount with '
        'AmountOutOfBounds before any task exists; script that with '
        'initFails(...).',
      );
    }

    var error = run.error;
    if (error == null && Decimal.parse(route.toAmountMin) < guard) {
      if (run.ladder != null || run.outcome != null) {
        throw ArgumentError(
          'The executed route guarantees ${route.toAmountMin}, below the '
          'accepted min_to_amount $minToAmount, so the engine fails the run '
          'QuoteWorsened while FetchingQuote.',
        );
      }
      error = RoutedSwapRunError.quoteWorsened(freshRoute: route);
    }
    final fresh = error?.freshRoute;
    if (fresh != null && Decimal.parse(fresh.toAmountMin) >= guard) {
      throw ArgumentError(
        'QuoteWorsened needs a fresh amount_min below the accepted '
        'min_to_amount $minToAmount; ${fresh.toAmountMin} passes the guard.',
      );
    }

    final source = run.sourceTxHash ?? _txHash('b0', seq);
    final url = run.providerExplorerUrl ?? 'https://scan.li.fi/tx/$source';
    final ladder =
        run.ladder ??
        _defaultLadder(
          run,
          route,
          error,
          run.approvalTxHashes ?? [_txHash('a1', seq), _txHash('a2', seq)],
          url,
        );
    RoutedSwapRun._checkLadder(
      ladder,
      crossChain: route.crossChain,
      error: error,
      outcome: run.outcome,
    );
    if (ladder.length > 1 && Decimal.parse(route.toAmountMin) < guard) {
      throw ArgumentError(
        'The executed route guarantees ${route.toAmountMin}, below the '
        'accepted min_to_amount $minToAmount: the engine fails QuoteWorsened '
        'while FetchingQuote and never reaches ${ladder.last.state.wire}.',
      );
    }

    final routeJson = route.toJson(amount: amount);
    return _Plan._(
      run: run,
      uuid: uuid,
      from: from,
      to: to,
      amount: amount,
      minToAmount: minToAmount,
      route: route,
      routeJson: routeJson,
      ladder: ladder,
      error: error,
      sourceTxHash: source,
      gasCoin:
          run.gasCoin ??
          route.approval?.gasCoin ??
          (route.gasCosts.isEmpty ? 'ETH' : route.gasCosts.first.coin),
      okDetails: error != null
          ? null
          : _okDetails(
              run,
              uuid: uuid,
              route: route,
              routeJson: routeJson,
              to: to,
              amount: amount,
              guard: guard,
              source: source,
              dest: run.destTxHash ?? _txHash('d0', seq),
              url: url,
            ),
    );
  }

  final RoutedSwapRun run;
  final String uuid;
  final String from;
  final String to;
  final String amount;
  final String minToAmount;
  final RoutedSwapQuote route;
  final Map<String, dynamic> routeJson;
  final List<RoutedSwapTick> ladder;
  final RoutedSwapRunError? error;
  final String sourceTxHash;
  final String gasCoin;
  final Map<String, dynamic>? okDetails;

  Map<String, dynamic> get initialDetails => _inProgress(ladder.first, null);

  /// Everything after the `FetchingQuote` persisted at init.
  List<_Transition> liveTransitions() =>
      transitions(ladder.sublist(1), previous: ladder.first);

  /// [ticks] then the terminal result. Stages restart from `unknown`, as
  /// each `track_bridge` call does.
  List<_Transition> transitions(
    List<RoutedSwapTick> ticks, {
    required RoutedSwapTick? previous,
  }) {
    final out = <_Transition>[];
    var stage = 'unknown';
    var before = previous;
    for (final tick in ticks) {
      String? tickStage;
      if (tick.state == RoutedSwapRunState.trackingBridge) {
        stage = _advanceStage(stage, _observedStage(tick.substatus));
        tickStage = stage;
      }
      out.add(
        _Transition.progress(_inProgress(tick, tickStage), _gasAfter(before)),
      );
      before = tick;
    }
    final error = this.error;
    final terminal = error == null
        ? _Terminal(ok: true, details: okDetails!)
        : _Terminal(
            ok: false,
            details: errorDetails(
              error,
              withRoute: ladder.last.state != RoutedSwapRunState.fetchingQuote,
            ),
          );
    final unconfirmed =
        error?.errorType == 'SwapTxFailed' &&
        error?.reason == 'source_transaction_not_confirmed';
    out.add(
      _Transition.terminal(
        terminal,
        unconfirmed ? const <_Gas>[] : _gasAfter(before),
      ),
    );
    return out;
  }

  /// `record_gas` runs once a transaction's confirmation wait ends, before
  /// the next transition is persisted.
  List<_Gas> _gasAfter(RoutedSwapTick? tick) {
    final approval = tick?.approveTxHash;
    if (approval != null) return [_Gas(approval, gasCoin, run.approvalGas)];
    if (tick?.state == RoutedSwapRunState.waitingSourceConfirmation) {
      return [_Gas(sourceTxHash, gasCoin, run.sourceGas)];
    }
    return const [];
  }

  /// `RoutedSwapInProgressStatus`: the tag first, then the fields, with
  /// `executed_route` on every state after `FetchingQuote`.
  Map<String, dynamic> _inProgress(RoutedSwapTick tick, String? stage) {
    final state = tick.state;
    return {
      'state': state.wire,
      'uuid': uuid,
      'provider': _provider,
      if (state != RoutedSwapRunState.fetchingQuote)
        'executed_route': routeJson,
      if (state == RoutedSwapRunState.approving)
        'approve_tx_hash': ?tick.approveTxHash,
      if (state == RoutedSwapRunState.broadcasting && tick.withSourceTxHash)
        'source_tx_hash': sourceTxHash,
      if (state == RoutedSwapRunState.waitingSourceConfirmation)
        'source_tx_hash': sourceTxHash,
      if (state == RoutedSwapRunState.trackingBridge) ...{
        'source_tx_hash': sourceTxHash,
        'stage': stage,
        'substatus': ?tick.substatus,
        'substatus_message': ?tick.substatusMessage,
        'provider_explorer_url': ?tick.providerExplorerUrl,
        'execution_duration_s': route.executionDurationS,
      },
    };
  }

  /// The serialized `MmError<RoutedSwapTaskError>`: `error`, `error_path`
  /// and `error_trace`, then `uuid`, `provider` and `executed_route` hoisted
  /// beside `error_type` — never inside `error_data`.
  Map<String, dynamic> errorDetails(
    RoutedSwapRunError error, {
    required bool withRoute,
  }) => {
    'error': error._messageFor(sourceTxHash),
    'error_path': 'swap_task',
    'error_trace': 'swap_task:1]',
    'uuid': uuid,
    'provider': _provider,
    if (withRoute) 'executed_route': routeJson,
    'error_type': error.errorType,
    'error_data': error._dataFor(sourceTxHash, amount),
  };

  static List<RoutedSwapTick> _defaultLadder(
    RoutedSwapRun run,
    RoutedSwapQuote route,
    RoutedSwapRunError? error,
    List<String> approvalHashes,
    String url,
  ) {
    final type = error?.errorType;
    final ladder = <RoutedSwapTick>[RoutedSwapTick.fetchingQuote];
    if (error != null && error._raisedByFreshQuote) return ladder;
    ladder.add(RoutedSwapTick.checkingAllowance);
    if (type == 'InsufficientBalance' ||
        type == 'PreflightRejected' ||
        type == 'InternalError') {
      return ladder;
    }
    final approval = route.approval;
    if (approval != null || type == 'ApprovalFailed') {
      final resets = approval?.resetsFirst ?? false;
      if (approvalHashes.length < (resets ? 2 : 1)) {
        throw ArgumentError('approvalTxHashes is short for this approval.');
      }
      final hashes = approvalHashes.take(resets ? 2 : 1).toList();
      ladder.add(const RoutedSwapTick.approving());
      if (type == 'ApprovalFailed') {
        switch (error!.reason) {
          case 'approval_broadcast_failed':
            break;
          case 'approval_transaction_failed' || 'allowance_reset_not_confirmed':
            ladder.add(RoutedSwapTick.approving(hashes.first));
          default:
            ladder.addAll(hashes.map(RoutedSwapTick.approving));
        }
        return ladder;
      }
      ladder.addAll(hashes.map(RoutedSwapTick.approving));
    }
    ladder.add(RoutedSwapTick.signing);
    if (type == 'SigningRejected') return ladder;
    ladder
      ..add(const RoutedSwapTick.broadcasting())
      ..add(RoutedSwapTick.waitingSourceConfirmation);
    if (type == 'SwapTxFailed' || !route.crossChain) return ladder;
    ladder
      ..add(const RoutedSwapTick.trackingBridge())
      ..addAll(run.tracking ?? const []);
    if (type == 'BridgeFailed') {
      return ladder..add(
        RoutedSwapTick.trackingBridge(
          substatus: error!.substatus,
          substatusMessage: error.substatusMessage,
          providerExplorerUrl: error.providerExplorerUrl,
        ),
      );
    }
    if (run.tracking != null) return ladder;
    return ladder..addAll(switch (run.outcome) {
      RoutedSwapRunOutcome.refunded => [
        RoutedSwapTick.trackingBridge(
          substatus: 'REFUND_IN_PROGRESS',
          substatusMessage: 'The refund is in progress.',
          providerExplorerUrl: url,
        ),
        RoutedSwapTick.trackingBridge(
          substatus: 'REFUNDED',
          substatusMessage: 'The transfer was refunded.',
          providerExplorerUrl: url,
        ),
      ],
      _ => [
        RoutedSwapTick.trackingBridge(
          substatus: 'WAIT_DESTINATION_TRANSACTION',
          substatusMessage: 'Waiting for the destination transaction.',
          providerExplorerUrl: url,
        ),
        if (run.outcome == RoutedSwapRunOutcome.partial)
          RoutedSwapTick.trackingBridge(
            substatus: 'PARTIAL',
            substatusMessage: 'The transfer was partially completed.',
            providerExplorerUrl: url,
          )
        else
          RoutedSwapTick.trackingBridge(
            substatus: 'COMPLETED',
            substatusMessage: 'The transfer is complete.',
            providerExplorerUrl: url,
          ),
      ],
    });
  }

  /// `RoutedSwapOutcome`, classified the way `terminal_status` classifies:
  /// `completed` only for the requested coin at or above the accepted
  /// minimum.
  static Map<String, dynamic> _okDetails(
    RoutedSwapRun run, {
    required String uuid,
    required RoutedSwapQuote route,
    required Map<String, dynamic> routeJson,
    required String to,
    required String amount,
    required Decimal guard,
    required String source,
    required String dest,
    required String url,
  }) {
    final outcome = run.outcome ?? RoutedSwapRunOutcome.completed;
    final head = {
      'outcome': outcome.wire,
      'uuid': uuid,
      'provider': _provider,
      'executed_route': routeJson,
    };
    if (!route.crossChain) {
      if (outcome != RoutedSwapRunOutcome.completed ||
          run.receivedCoin != null ||
          run.receivedSymbol != null ||
          run.receivedAmount != null ||
          run.destTxHash != null) {
        throw ArgumentError(
          'A same-chain swap only completes: it receives the executed '
          "route's quoted to.amount and has no destination transaction.",
        );
      }
      return {
        ...head,
        'received': {'coin': route.to, 'amount': route.toAmount},
        'source_tx_hash': source,
      };
    }

    final symbol = run.receivedSymbol;
    final coin = symbol != null
        ? null
        : run.receivedCoin ??
              (outcome == RoutedSwapRunOutcome.refunded ? route.from : to);
    final received =
        run.receivedAmount ??
        (outcome == RoutedSwapRunOutcome.refunded ? amount : route.toAmount);
    final requested = coin == to;
    final enough = _decimal(received, 'receivedAmount') >= guard;
    switch (outcome) {
      case RoutedSwapRunOutcome.completed:
        if (!requested || !enough) {
          throw ArgumentError(
            'The engine completes only the requested coin at or above the '
            'accepted minimum; this delivery is partial.',
          );
        }
      case RoutedSwapRunOutcome.partial:
        final classified = requested ? 'below_minimum' : 'intermediate_token';
        if (requested && enough || classified != run.partialReason) {
          throw ArgumentError(
            'The engine classifies this delivery as '
            '${requested && enough ? 'completed' : classified}, not '
            '${run.partialReason}.',
          );
        }
      case RoutedSwapRunOutcome.refunded:
        if (run.destTxHash != null) {
          throw ArgumentError('A refund has no destination transaction.');
        }
    }
    return {
      ...head,
      'partial_reason': ?run.partialReason,
      'received': {'coin': ?coin, 'symbol': ?symbol, 'amount': received},
      'source_tx_hash': source,
      if (outcome != RoutedSwapRunOutcome.refunded) 'dest_tx_hash': dest,
      'provider_explorer_url': url,
    };
  }
}
