part of 'routed_swap_fixture.dart';

/// One scripted execution: what `task::routed_swap::init` starts.
///
/// The [ladder] is the list of transitions the engine persists; it defaults to
/// the path the engine takes for the route, [error] and [outcome]. Status
/// reads observe it (see [pollsPerState]); history sees every transition.
class RoutedSwapRun {
  /// Scripts one execution. Throws [ArgumentError] for a combination the
  /// engine cannot produce; checks that need the `init` request run there.
  RoutedSwapRun({
    this.route,
    this.ladder,
    this.tracking,
    this.outcome,
    this.partialReason,
    this.receivedCoin,
    this.receivedSymbol,
    this.receivedAmount,
    this.error,
    this.sourceTxHash,
    this.approvalTxHashes,
    this.destTxHash,
    this.providerExplorerUrl,
    this.gasCoin,
    this.approvalGas = '0.0021',
    this.sourceGas = '0.0134',
    this.autoAdvance = true,
    this.pollsPerState = 1,
    this.advanceOnInit = 0,
  }) {
    if (error != null && outcome != null) {
      throw ArgumentError('A run ends in error or in an outcome, not both.');
    }
    if (receivedCoin != null && receivedSymbol != null) {
      throw ArgumentError('`received` names a coin or a symbol, not both.');
    }
    if ((outcome == RoutedSwapRunOutcome.partial) != (partialReason != null)) {
      throw ArgumentError(
        'partial_reason is present exactly on a partial outcome.',
      );
    }
    if (partialReason != null) {
      RoutedSwapRunError._checkOneOf(partialReason!, 'partialReason', const {
        'below_minimum',
        'intermediate_token',
      });
      if (receivedAmount == null) {
        throw ArgumentError('A partial outcome needs its receivedAmount.');
      }
    }
    if (pollsPerState < 1) {
      throw ArgumentError.value(pollsPerState, 'pollsPerState');
    }
    if (advanceOnInit < 0) {
      throw ArgumentError.value(advanceOnInit, 'advanceOnInit');
    }
    final tracking = this.tracking;
    if (tracking != null) {
      if (this.ladder != null) {
        throw ArgumentError('tracking shapes the default ladder only.');
      }
      if (tracking.any((t) => t.state != RoutedSwapRunState.trackingBridge)) {
        throw ArgumentError('tracking lists TrackingBridge ticks only.');
      }
      final route = this.route;
      if (route != null && !route.crossChain) {
        throw ArgumentError('Same-chain swaps never enter TrackingBridge.');
      }
    }
    final ladder = this.ladder;
    if (ladder != null) {
      _checkLadder(
        ladder,
        crossChain: route?.crossChain,
        error: error,
        outcome: outcome,
      );
    }
  }

  /// The executed route. Defaults to the scripted quote for the pair, else a
  /// route whose minimum is exactly the accepted `min_to_amount`. A route
  /// whose minimum is below the accepted one fails `QuoteWorsened`, as the
  /// engine's guard does.
  final RoutedSwapQuote? route;

  /// The persisted transitions, starting at `FetchingQuote`.
  final List<RoutedSwapTick>? ladder;

  /// `TrackingBridge` ticks after the initial one, for the default ladder.
  final List<RoutedSwapTick>? tracking;

  /// The terminal `Ok` outcome; `completed` when neither this nor [error] is
  /// set.
  final RoutedSwapRunOutcome? outcome;

  /// `below_minimum` or `intermediate_token`, on a partial outcome.
  final String? partialReason;

  /// The received coin: the requested one by default, the source coin for a
  /// refund.
  final String? receivedCoin;

  /// A received provider symbol with no KDF ticker.
  final String? receivedSymbol;

  /// The received amount: the route's `to.amount` by default, the sold amount
  /// for a refund.
  final String? receivedAmount;

  /// The terminal task error.
  final RoutedSwapRunError? error;

  /// The source transaction hash.
  final String? sourceTxHash;

  /// Hashes the default ladder broadcasts approvals with, in order.
  final List<String>? approvalTxHashes;

  /// The destination transaction hash of a cross-chain delivery.
  final String? destTxHash;

  /// The provider's explorer link.
  final String? providerExplorerUrl;

  /// The coin paying gas: the route's approval gas coin, else its first gas
  /// coin, else `ETH`.
  final String? gasCoin;

  /// Actual gas of each approval transaction.
  final String approvalGas;

  /// Actual gas of the source transaction.
  final String sourceGas;

  /// Whether a status read advances the swap. When false only
  /// [RoutedSwapFixture.advance] does.
  final bool autoAdvance;

  /// Status reads that report each state before the next read advances.
  final int pollsPerState;

  /// Transitions applied during `init`, before the first status read — a
  /// task that raced ahead of it.
  final int advanceOnInit;

  static void _checkLadder(
    List<RoutedSwapTick> ladder, {
    required bool? crossChain,
    required RoutedSwapRunError? error,
    required RoutedSwapRunOutcome? outcome,
  }) {
    if (ladder.isEmpty ||
        ladder.first.state != RoutedSwapRunState.fetchingQuote) {
      throw ArgumentError(
        'A ladder starts at FetchingQuote: init persists it before the task '
        'runs.',
      );
    }
    const successors = <RoutedSwapRunState, Set<RoutedSwapRunState>>{
      RoutedSwapRunState.fetchingQuote: {RoutedSwapRunState.checkingAllowance},
      RoutedSwapRunState.checkingAllowance: {
        RoutedSwapRunState.approving,
        RoutedSwapRunState.signing,
      },
      RoutedSwapRunState.approving: {
        RoutedSwapRunState.approving,
        RoutedSwapRunState.signing,
      },
      RoutedSwapRunState.signing: {RoutedSwapRunState.broadcasting},
      RoutedSwapRunState.broadcasting: {
        RoutedSwapRunState.waitingSourceConfirmation,
      },
      RoutedSwapRunState.waitingSourceConfirmation: {
        RoutedSwapRunState.trackingBridge,
      },
      RoutedSwapRunState.trackingBridge: {RoutedSwapRunState.trackingBridge},
    };
    final approvals = <String>{};
    var tracked = false;
    for (var i = 1; i < ladder.length; i++) {
      final previous = ladder[i - 1].state;
      final tick = ladder[i];
      if (!successors[previous]!.contains(tick.state)) {
        throw ArgumentError(
          '${tick.state.wire} cannot follow ${previous.wire}. The engine '
          'persists FetchingQuote, CheckingAllowance, [Approving...], '
          'Signing, Broadcasting, WaitingSourceConfirmation, '
          '[TrackingBridge...] in that order.',
        );
      }
      if (tick.state == RoutedSwapRunState.approving) {
        final hash = tick.approveTxHash;
        if (previous != RoutedSwapRunState.approving) {
          if (hash != null) {
            throw ArgumentError(
              'The first Approving is persisted before any approval is '
              'broadcast, so it has no approve_tx_hash.',
            );
          }
        } else if (hash == null || !approvals.add(hash)) {
          throw ArgumentError(
            'A later Approving carries the new hash just broadcast.',
          );
        } else if (approvals.length > 2) {
          throw ArgumentError(
            'At most two approvals: a zero-reset, then the exact amount.',
          );
        }
      }
      if (tick.state == RoutedSwapRunState.trackingBridge) {
        if (crossChain == false) {
          throw ArgumentError('Same-chain swaps never enter TrackingBridge.');
        }
        if (!tracked &&
            (tick.substatus != null ||
                tick.substatusMessage != null ||
                tick.providerExplorerUrl != null)) {
          throw ArgumentError(
            'The first TrackingBridge is persisted before the provider '
            'reports anything.',
          );
        }
        tracked = true;
      }
    }
    _checkRaisePoint(
      ladder.last,
      crossChain: crossChain,
      error: error,
      outcome: outcome,
    );
  }

  static void _checkRaisePoint(
    RoutedSwapTick last, {
    required bool? crossChain,
    required RoutedSwapRunError? error,
    required RoutedSwapRunOutcome? outcome,
  }) {
    final state = last.state;
    final String where;
    final bool possible;
    if (error == null) {
      where =
          'an Ok outcome after WaitingSourceConfirmation (same-chain) or '
          'TrackingBridge (cross-chain)';
      possible = switch (crossChain) {
        true => state == RoutedSwapRunState.trackingBridge,
        false => state == RoutedSwapRunState.waitingSourceConfirmation,
        null =>
          state == RoutedSwapRunState.trackingBridge ||
              state == RoutedSwapRunState.waitingSourceConfirmation,
      };
    } else {
      switch (error.errorType) {
        case 'QuoteWorsened' ||
            'NoRouteFound' ||
            'RateLimited' ||
            'ProviderApiError' ||
            'AmountOutOfBounds':
          where = '${error.errorType} while FetchingQuote';
          possible = state == RoutedSwapRunState.fetchingQuote;
        case 'InsufficientBalance':
          where =
              'InsufficientBalance at CheckingAllowance, before any '
              'approval';
          possible = state == RoutedSwapRunState.checkingAllowance;
        case 'PreflightRejected':
          where = 'PreflightRejected at CheckingAllowance or Approving';
          possible =
              state == RoutedSwapRunState.checkingAllowance ||
              state == RoutedSwapRunState.approving;
        case 'ApprovalFailed':
          where =
              'ApprovalFailed at Approving, with the hash of the approval '
              'that failed unless it was never broadcast';
          possible =
              state == RoutedSwapRunState.approving &&
              (error.reason == 'approval_broadcast_failed' ||
                  last.approveTxHash != null);
        case 'SigningRejected':
          where =
              'SigningRejected at Approving, Signing, or a Broadcasting '
              'handoff that has no hash yet';
          possible =
              state == RoutedSwapRunState.approving ||
              state == RoutedSwapRunState.signing ||
              (state == RoutedSwapRunState.broadcasting &&
                  !last.withSourceTxHash);
        case 'SwapTxFailed':
          where = 'SwapTxFailed at WaitingSourceConfirmation';
          possible = state == RoutedSwapRunState.waitingSourceConfirmation;
        case 'BridgeFailed':
          where = 'BridgeFailed at TrackingBridge, cross-chain only';
          possible =
              state == RoutedSwapRunState.trackingBridge &&
              (crossChain ?? true);
        case 'TransportError':
          where = 'TransportError before Broadcasting';
          possible = !state.isPostBroadcast;
        default:
          where = '${error.errorType} anywhere';
          possible = true;
      }
    }
    if (!possible) {
      throw ArgumentError(
        'The engine raises $where; this ladder ends at ${state.wire}.',
      );
    }
  }
}

// ------------------------------------------------------------------ private
