part of 'routed_swap_manager.dart';

/// Turns engine status and history into progress snapshots.
extension _RoutedSwapProgressMapping on RoutedSwapManager {
  RoutedSwapProgress _progressFromStatus(
    rpc.RoutedSwapStatus status, {
    RoutedSwapOffer? accepted,
    RoutedSwapOffer? previousExecuted,
    List<String> approvalTxHashes = const [],
    RoutedSwapPhase? lastLivePhase,
    bool fromHistory = false,
  }) {
    final executed = _offerFromExecuted(
      status.executedRoute,
      accepted,
      previous: previousExecuted,
    );
    switch (status) {
      case rpc.RoutedSwapInProgress():
        final hashes = [
          ...approvalTxHashes,
          if (status.approveTxHash != null &&
              !approvalTxHashes.contains(status.approveTxHash))
            status.approveTxHash!,
        ];
        return RoutedSwapProgress(
          uuid: status.uuid,
          provider: status.provider,
          phase: _phaseOf(status.state),
          // A record recovered from history has no addressable task, so there
          // is nothing to cancel even when the phase would otherwise allow it.
          canCancel: !fromHistory && status.state.isCancellable,
          rawState: status.rawState,
          bridgeStage: status.stage,
          acceptedOffer: accepted,
          executedOffer: executed,
          approvalTxHashes: hashes,
          sourceTxHash: status.sourceTxHash,
          explorerUrl: status.providerExplorerUrl,
          providerStatusDetail: status.substatusMessage ?? status.substatus,
          estimatedDuration: status.executionDurationS == null
              ? executed?.estimatedDuration
              : Duration(seconds: status.executionDurationS!),
          actionUrl: status.actionUrl,
        );
      case rpc.RoutedSwapFinished():
        return RoutedSwapProgress(
          uuid: status.uuid,
          provider: status.provider,
          phase: RoutedSwapPhase.finished,
          canCancel: false,
          acceptedOffer: accepted,
          executedOffer: executed,
          receipt: RoutedSwapReceipt(
            outcome: status.outcome,
            partialReason: status.partialReason,
            amount: Decimal.parse(status.received.amount),
            assetId: _resolveAssetOf(status.received),
            symbol: status.received.symbol,
          ),
          approvalTxHashes: approvalTxHashes,
          sourceTxHash: status.sourceTxHash,
          destinationTxHash: status.destTxHash,
          explorerUrl: status.providerExplorerUrl,
        );
      case rpc.RoutedSwapErrored():
        final failure = _failureFrom(
          status,
          accepted: accepted ?? executed,
          approvalTxHashes: approvalTxHashes,
          lastLivePhase: lastLivePhase,
        );
        return RoutedSwapProgress(
          uuid: status.uuid,
          provider: status.provider,
          phase: RoutedSwapPhase.failed,
          canCancel: false,
          acceptedOffer: accepted,
          executedOffer: executed,
          failure: failure,
          approvalTxHashes: approvalTxHashes,
          sourceTxHash: failure.sourceTxHash,
          explorerUrl: failure.providerExplorerUrl,
        );
    }
  }

  RoutedSwapProgress _progressFromEntry(
    rpc.RoutedSwapHistoryEntry entry, {
    RoutedSwapOffer? accepted,
    RoutedSwapProgress? previous,
    RoutedSwapPhase? lastLivePhase,
  }) {
    final hashes = entry.approvalTxHashes.isNotEmpty
        ? entry.approvalTxHashes
        : previous?.approvalTxHashes ?? const <String>[];
    final base = _progressFromStatus(
      entry.swap,
      accepted: accepted,
      previousExecuted: previous?.executedOffer,
      approvalTxHashes: hashes,
      // Only a phase this process watched live can prove a failure happened
      // before broadcast.
      lastLivePhase: lastLivePhase,
      fromHistory: true,
    );
    final requested = entry.requested;
    return base.copyWith(
      approvalTxHashes: hashes,
      createdAt: _fromUnix(entry.createdAt),
      updatedAt: _fromUnix(entry.updatedAt),
      finishedAt: _fromUnix(entry.finishedAt),
      requested: RoutedSwapRequest(
        fromTicker: requested.from,
        toTicker: requested.to,
        from: _resolveAsset(requested.from),
        to: _resolveAsset(requested.to),
        amount: Decimal.tryParse(requested.amount) ?? Decimal.zero,
      ),
      minToAmountAccepted: _decimal(entry.minToAmountAccepted),
      gasSpent: [
        for (final gas in entry.gasSpent)
          RoutedSwapGasPaid(
            txHash: gas.txHash.isEmpty ? null : gas.txHash,
            ticker: gas.coin,
            assetId: _resolveAsset(gas.coin),
            amount: Decimal.tryParse(gas.amount) ?? Decimal.zero,
          ),
      ],
      totalGasSpent: [
        for (final gas in entry.totalGasSpent)
          RoutedSwapGasPaid(
            ticker: gas.coin,
            assetId: _resolveAsset(gas.coin),
            amount: Decimal.tryParse(gas.amount) ?? Decimal.zero,
          ),
      ],
    );
  }

  RoutedSwapFailure _failureFrom(
    rpc.RoutedSwapErrored status, {
    required List<String> approvalTxHashes,
    RoutedSwapOffer? accepted,
    RoutedSwapPhase? lastLivePhase,
  }) {
    final error = status.error;
    final kind = switch (error) {
      rpc.RoutedSwapQuoteWorsenedError() => RoutedSwapFailureKind.priceMoved,
      rpc.RoutedSwapInsufficientBalanceError() =>
        RoutedSwapFailureKind.insufficientBalance,
      rpc.RoutedSwapApprovalFailedError() =>
        RoutedSwapFailureKind.approvalFailed,
      rpc.RoutedSwapTxFailedError() =>
        RoutedSwapFailureKind.swapTransactionFailed,
      rpc.RoutedSwapSigningRejectedError() =>
        RoutedSwapFailureKind.signingRejected,
      rpc.RoutedSwapBridgeFailedError() => RoutedSwapFailureKind.bridgeFailed,
      rpc.RoutedSwapPreflightRejectedError() =>
        RoutedSwapFailureKind.preflightRejected,
      rpc.RoutedSwapNoRouteTaskError() ||
      rpc.RoutedSwapRateLimitedTaskError() ||
      rpc.RoutedSwapProviderTaskError() ||
      rpc.RoutedSwapAmountOutOfBoundsTaskError() =>
        RoutedSwapFailureKind.quoteUnavailable,
      rpc.RoutedSwapAbortedOnRestartError() =>
        RoutedSwapFailureKind.abortedOnRestart,
      rpc.RoutedSwapTaskCancelledError() => RoutedSwapFailureKind.cancelled,
      rpc.RoutedSwapInternalTaskError() ||
      rpc.RoutedSwapTransportTaskError() => RoutedSwapFailureKind.internalError,
      rpc.RoutedSwapUnknownTaskError() => RoutedSwapFailureKind.unknown,
    };

    final movement = _fundsMovementOf(
      error,
      approved: approvalTxHashes.isNotEmpty,
      lastLivePhase: lastLivePhase,
    );

    RoutedSwapOffer? freshOffer;
    if (error case rpc.RoutedSwapQuoteWorsenedError(:final freshRoute?)) {
      final from = accepted?.from ?? _resolveAssetOf(freshRoute.from);
      final to = accepted?.to ?? _resolveAssetOf(freshRoute.toMinimum);
      if (from != null && to != null) {
        freshOffer = _offerFrom(
          freshRoute,
          from: from,
          to: to,
          order: accepted?.order,
          slippage: accepted?.slippage,
        );
      }
    }

    return RoutedSwapFailure(
      kind: kind,
      errorType: status.errorType,
      message: status.message,
      fundsMovement: movement,
      retryPolicy: _retryPolicyOf(error, movement),
      details: switch (error) {
        rpc.RoutedSwapUnknownTaskError(:final data) => data,
        _ => const {},
      },
      freshOffer: freshOffer,
      approvalFailureReason: switch (error) {
        rpc.RoutedSwapApprovalFailedError(:final reason) => reason,
        _ => null,
      },
      txFailureReason: switch (error) {
        rpc.RoutedSwapTxFailedError(:final reason) => reason,
        _ => null,
      },
      signingRejectionReason: switch (error) {
        rpc.RoutedSwapSigningRejectedError(:final reason) => reason,
        _ => null,
      },
      preflightCheck: switch (error) {
        rpc.RoutedSwapPreflightRejectedError(:final check) => check,
        _ => null,
      },
      shortfall: switch (error) {
        rpc.RoutedSwapInsufficientBalanceError(
          :final coin,
          :final available,
          :final required,
        ) =>
          RoutedSwapShortfall(
            ticker: coin,
            assetId: _resolveAsset(coin),
            available: Decimal.tryParse(available) ?? Decimal.zero,
            required: Decimal.tryParse(required) ?? Decimal.zero,
          ),
        _ => null,
      },
      bounds: switch (error) {
        rpc.RoutedSwapAmountOutOfBoundsTaskError(:final min, :final max) =>
          RoutedSwapAmountBounds(min: _decimal(min), max: _decimal(max)),
        _ => null,
      },
      noRouteReasons: switch (error) {
        rpc.RoutedSwapNoRouteTaskError(:final reasons) => reasons,
        _ => const [],
      },
      providerRequestId: error.providerRequestId,
      sourceTxHash: switch (error) {
        rpc.RoutedSwapTxFailedError(:final sourceTxHash) => sourceTxHash,
        rpc.RoutedSwapBridgeFailedError(:final sourceTxHash) => sourceTxHash,
        _ => null,
      },
      providerExplorerUrl: switch (error) {
        rpc.RoutedSwapBridgeFailedError(:final providerExplorerUrl) =>
          providerExplorerUrl,
        _ => null,
      },
    );
  }
}

int _unixSeconds(DateTime time) => time.toUtc().millisecondsSinceEpoch ~/ 1000;

DateTime? _fromUnix(int? seconds) => seconds == null || seconds == 0
    ? null
    : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

/// Whether the sold funds moved, never claiming "untouched" without proof.
RoutedSwapFundsMovement _fundsMovementOf(
  rpc.RoutedSwapTaskError error, {
  required bool approved,
  RoutedSwapPhase? lastLivePhase,
}) {
  final untouched = approved
      ? RoutedSwapFundsMovement.feesOnly
      : RoutedSwapFundsMovement.none;
  final watchedBeforeBroadcast =
      lastLivePhase != null && _isPreBroadcast(lastLivePhase);

  switch (error) {
    case rpc.RoutedSwapTxFailedError(:final reason):
      return reason == rpc.RoutedSwapTxFailureReason.sourceTransactionReverted
          ? RoutedSwapFundsMovement.feesOnly
          : RoutedSwapFundsMovement.uncertain;
    case rpc.RoutedSwapBridgeFailedError():
      return RoutedSwapFundsMovement.sent;
    case rpc.RoutedSwapApprovalFailedError(:final reason):
      // The swap never went out; an approval or reset may still have cost
      // gas.
      return !approved &&
              reason ==
                  rpc.RoutedSwapApprovalFailureReason.approvalBroadcastFailed
          ? RoutedSwapFundsMovement.none
          : RoutedSwapFundsMovement.feesOnly;
    case rpc.RoutedSwapSigningRejectedError(:final reason):
      if (reason != rpc.RoutedSwapSigningRejectionReason.timeout) {
        return untouched;
      }
      return watchedBeforeBroadcast
          ? untouched
          : RoutedSwapFundsMovement.uncertain;
    case rpc.RoutedSwapInternalTaskError():
      // Rare, but it can follow an uncertain wallet handoff after
      // Broadcasting; only a live observation before broadcast rules that
      // out.
      return watchedBeforeBroadcast
          ? untouched
          : RoutedSwapFundsMovement.uncertain;
    case rpc.RoutedSwapUnknownTaskError():
      return RoutedSwapFundsMovement.uncertain;
    default:
      return error.isPreBroadcast
          ? untouched
          : RoutedSwapFundsMovement.uncertain;
  }
}

bool _isPreBroadcast(RoutedSwapPhase phase) =>
    phase == RoutedSwapPhase.preparing ||
    phase == RoutedSwapPhase.approving ||
    phase == RoutedSwapPhase.signing;

RoutedSwapRetryPolicy _retryPolicyOf(
  rpc.RoutedSwapTaskError error,
  RoutedSwapFundsMovement movement,
) {
  return switch (error) {
    rpc.RoutedSwapQuoteWorsenedError() => RoutedSwapRetryPolicy.requote,
    rpc.RoutedSwapInsufficientBalanceError() =>
      RoutedSwapRetryPolicy.fixAndRetry,
    rpc.RoutedSwapApprovalFailedError() => RoutedSwapRetryPolicy.retry,
    rpc.RoutedSwapTxFailedError(:final reason) =>
      reason == rpc.RoutedSwapTxFailureReason.sourceTransactionReverted
          ? RoutedSwapRetryPolicy.requote
          : RoutedSwapRetryPolicy.wait,
    rpc.RoutedSwapSigningRejectedError() =>
      movement == RoutedSwapFundsMovement.uncertain
          ? RoutedSwapRetryPolicy.wait
          : RoutedSwapRetryPolicy.retry,
    rpc.RoutedSwapBridgeFailedError() => RoutedSwapRetryPolicy.contactSupport,
    rpc.RoutedSwapPreflightRejectedError(:final check) =>
      check.isRetryable
          ? RoutedSwapRetryPolicy.retry
          : check.mayPassOnRequote
          ? RoutedSwapRetryPolicy.requote
          : RoutedSwapRetryPolicy.contactSupport,
    rpc.RoutedSwapRateLimitedTaskError() ||
    rpc.RoutedSwapProviderTaskError() => RoutedSwapRetryPolicy.retry,
    rpc.RoutedSwapNoRouteTaskError() ||
    rpc.RoutedSwapAmountOutOfBoundsTaskError() => RoutedSwapRetryPolicy.requote,
    rpc.RoutedSwapAbortedOnRestartError() ||
    rpc.RoutedSwapTaskCancelledError() => RoutedSwapRetryPolicy.retry,
    rpc.RoutedSwapInternalTaskError() || rpc.RoutedSwapTransportTaskError() =>
      movement == RoutedSwapFundsMovement.uncertain
          ? RoutedSwapRetryPolicy.contactSupport
          : RoutedSwapRetryPolicy.retry,
    rpc.RoutedSwapUnknownTaskError() => RoutedSwapRetryPolicy.contactSupport,
  };
}

RoutedSwapPhase _phaseOf(rpc.RoutedSwapState state) => switch (state) {
  rpc.RoutedSwapState.fetchingQuote ||
  rpc.RoutedSwapState.checkingAllowance => RoutedSwapPhase.preparing,
  rpc.RoutedSwapState.approving => RoutedSwapPhase.approving,
  rpc.RoutedSwapState.signing => RoutedSwapPhase.signing,
  rpc.RoutedSwapState.broadcasting => RoutedSwapPhase.sending,
  rpc.RoutedSwapState.waitingSourceConfirmation => RoutedSwapPhase.confirming,
  rpc.RoutedSwapState.trackingBridge => RoutedSwapPhase.bridging,
  rpc.RoutedSwapState.unknown => RoutedSwapPhase.unknown,
};
