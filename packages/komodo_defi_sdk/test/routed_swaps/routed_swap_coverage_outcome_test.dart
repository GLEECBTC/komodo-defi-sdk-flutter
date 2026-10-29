import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:test/test.dart';

import 'routed_swap_coverage_fakes.dart';

RoutedSwapFailure _failure({
  RoutedSwapFundsMovement movement = RoutedSwapFundsMovement.none,
  RoutedSwapRetryPolicy policy = RoutedSwapRetryPolicy.retry,
  String message = 'failed',
}) => RoutedSwapFailure(
  kind: RoutedSwapFailureKind.internalError,
  errorType: 'InternalError',
  message: message,
  fundsMovement: movement,
  retryPolicy: policy,
);

RoutedSwapReceipt _receipt(RoutedSwapOutcome outcome) =>
    RoutedSwapReceipt(outcome: outcome, amount: d('99.4'), assetId: usdt);

RoutedSwapProgress _snapshot({
  RoutedSwapPhase phase = RoutedSwapPhase.bridging,
  RoutedSwapReceipt? receipt,
  List<String> approvals = const [],
  RoutedSwapOffer? accepted,
  RoutedSwapOffer? executed,
}) => RoutedSwapProgress(
  uuid: uuidOf(1),
  phase: phase,
  canCancel: false,
  receipt: receipt,
  approvalTxHashes: approvals,
  acceptedOffer: accepted,
  executedOffer: executed,
);

void main() {
  group('receipt', () {
    test('only a completed outcome is a success', () {
      for (final outcome in RoutedSwapOutcome.values) {
        expect(
          _receipt(outcome).isSuccess,
          outcome == RoutedSwapOutcome.completed,
          reason: '$outcome',
        );
      }
    });

    test('names the token by asset, else by provider symbol', () {
      expect(_receipt(RoutedSwapOutcome.completed).tokenLabel, 'USDT-PLG20');
      final symbol = RoutedSwapReceipt(
        outcome: RoutedSwapOutcome.partial,
        partialReason: RoutedSwapPartialReason.intermediateToken,
        amount: d('99.4'),
        symbol: 'axlUSDC',
      );
      expect(symbol.tokenLabel, 'axlUSDC');
      expect(
        RoutedSwapReceipt(
          outcome: RoutedSwapOutcome.completed,
          amount: d('1'),
        ).tokenLabel,
        isEmpty,
      );
      expect(
        _receipt(RoutedSwapOutcome.completed),
        _receipt(RoutedSwapOutcome.completed),
      );
      expect(
        _receipt(RoutedSwapOutcome.completed),
        isNot(_receipt(RoutedSwapOutcome.refunded)),
      );
    });
  });

  group('failure', () {
    test('funds are untouched only when nothing was broadcast', () {
      for (final movement in RoutedSwapFundsMovement.values) {
        expect(
          _failure(movement: movement).fundsUntouched,
          movement == RoutedSwapFundsMovement.none,
          reason: '$movement',
        );
      }
    });

    test('only a retry or a re-quote invites starting again', () {
      for (final policy in RoutedSwapRetryPolicy.values) {
        expect(
          _failure(policy: policy).isRetryable,
          policy == RoutedSwapRetryPolicy.retry ||
              policy == RoutedSwapRetryPolicy.requote,
          reason: '$policy',
        );
      }
    });

    test('defaults to no details, reasons or evidence', () {
      final failure = _failure();
      expect(failure.details, isEmpty);
      expect(failure.noRouteReasons, isEmpty);
      expect([
        failure.freshOffer,
        failure.approvalFailureReason,
        failure.txFailureReason,
        failure.signingRejectionReason,
        failure.preflightCheck,
        failure.shortfall,
        failure.bounds,
        failure.providerRequestId,
        failure.sourceTxHash,
        failure.providerExplorerUrl,
      ], everyElement(isNull));
      expect(_failure(), isNot(_failure(message: 'other')));
    });

    test('its parts compare by value', () {
      RoutedSwapShortfall short(String required) => RoutedSwapShortfall(
        ticker: 'ETH',
        assetId: eth,
        available: d('0.001'),
        required: d(required),
      );
      expect(short('0.0129'), short('0.0129'));
      expect(short('0.0129').hashCode, short('0.0129').hashCode);
      expect(short('0.0129'), isNot(short('0.02')));

      RoutedSwapAmountBounds bounds(String? max) =>
          RoutedSwapAmountBounds(min: d('1'), max: max == null ? null : d(max));
      expect(bounds('9'), bounds('9'));
      expect(bounds('9').hashCode, bounds('9').hashCode);
      expect(bounds('9'), isNot(bounds(null)));

      RoutedSwapRequest request(String amount) => RoutedSwapRequest(
        fromTicker: 'USDC-ERC20',
        toTicker: 'USDT-PLG20',
        from: usdc,
        to: usdt,
        amount: d(amount),
      );
      expect(request('100'), request('100'));
      expect(request('100').hashCode, request('100').hashCode);
      expect(request('100'), isNot(request('101')));

      RoutedSwapGasPaid gas(String? txHash) => RoutedSwapGasPaid(
        txHash: txHash,
        ticker: 'ETH',
        assetId: eth,
        amount: d('0.001'),
      );
      expect(gas('0xa'), gas('0xa'));
      expect(gas('0xa').hashCode, gas('0xa').hashCode);
      expect(gas('0xa'), isNot(gas(null)));
    });
  });

  group('progress', () {
    test('only finished and failed are terminal', () {
      for (final phase in RoutedSwapPhase.values) {
        expect(
          _snapshot(phase: phase).isTerminal,
          phase == RoutedSwapPhase.finished || phase == RoutedSwapPhase.failed,
          reason: '$phase',
        );
      }
    });

    test('a success needs a completed receipt', () {
      expect(_snapshot().isSuccess, isFalse);
      expect(
        _snapshot(
          phase: RoutedSwapPhase.finished,
          receipt: _receipt(RoutedSwapOutcome.completed),
        ).isSuccess,
        isTrue,
      );
      expect(
        _snapshot(
          phase: RoutedSwapPhase.finished,
          receipt: _receipt(RoutedSwapOutcome.refunded),
        ).isSuccess,
        isFalse,
      );
    });

    test('names the latest approval and the offer that fits best', () {
      expect(_snapshot().approvalTxHash, isNull);
      expect(
        _snapshot(approvals: ['0xreset', '0xexact']).approvalTxHash,
        '0xexact',
      );

      final accepted = offerOf();
      final executed = offerOf(kind: RoutedSwapRouteKind.sameChain);
      expect(_snapshot().offer, isNull);
      expect(_snapshot(accepted: accepted).offer, same(accepted));
      expect(
        _snapshot(accepted: accepted, executed: executed).offer,
        same(executed),
      );
    });

    test('copyWith replaces what it is given and keeps the rest', () {
      final base = RoutedSwapProgress(
        uuid: uuidOf(1),
        phase: RoutedSwapPhase.bridging,
        canCancel: false,
        provider: 'lifi',
        rawState: 'TrackingBridge',
        bridgeStage: RoutedSwapBridgeStage.bridging,
        executedOffer: offerOf(),
        receipt: _receipt(RoutedSwapOutcome.completed),
        failure: _failure(),
        approvalTxHashes: const ['0xa'],
        sourceTxHash: '0xsource',
        destinationTxHash: '0xdest',
        explorerUrl: 'https://scan.li.fi/tx/1',
        providerStatusDetail: 'WAIT_DESTINATION_TRANSACTION',
        estimatedDuration: const Duration(seconds: 95),
        actionUrl: 'https://li.fi/act',
      );
      final at = DateTime.utc(2026, 9, 25, 12);
      final gas = [RoutedSwapGasPaid(ticker: 'ETH', amount: d('0.001'))];
      final requested = RoutedSwapRequest(
        fromTicker: 'USDC-ERC20',
        toTicker: 'USDT-PLG20',
        amount: d('100'),
      );
      final changed = base.copyWith(
        acceptedOffer: offerOf(),
        approvalTxHashes: ['0xa', '0xb'],
        createdAt: at,
        updatedAt: at.add(const Duration(seconds: 1)),
        finishedAt: at.add(const Duration(seconds: 2)),
        requested: requested,
        minToAmountAccepted: d('99'),
        gasSpent: gas,
        totalGasSpent: gas,
        delayedSince: at.add(const Duration(seconds: 3)),
      );

      expect(changed.acceptedOffer, offerOf());
      expect(changed.approvalTxHashes, ['0xa', '0xb']);
      expect(changed.createdAt, at);
      expect(changed.updatedAt, at.add(const Duration(seconds: 1)));
      expect(changed.finishedAt, at.add(const Duration(seconds: 2)));
      expect(changed.requested, requested);
      expect(changed.minToAmountAccepted, Decimal.parse('99'));
      expect(changed.gasSpent, gas);
      expect(changed.totalGasSpent, gas);
      expect(changed.delayedSince, at.add(const Duration(seconds: 3)));
      expect(
        [
          changed.uuid,
          changed.phase,
          changed.canCancel,
          changed.provider,
          changed.rawState,
          changed.bridgeStage,
          changed.executedOffer,
          changed.receipt,
          changed.failure,
          changed.sourceTxHash,
          changed.destinationTxHash,
          changed.explorerUrl,
          changed.providerStatusDetail,
          changed.estimatedDuration,
          changed.actionUrl,
        ],
        [
          base.uuid,
          base.phase,
          base.canCancel,
          base.provider,
          base.rawState,
          base.bridgeStage,
          base.executedOffer,
          base.receipt,
          base.failure,
          base.sourceTxHash,
          base.destinationTxHash,
          base.explorerUrl,
          base.providerStatusDetail,
          base.estimatedDuration,
          base.actionUrl,
        ],
      );

      expect(base.copyWith(), base);
      expect(base.copyWith().hashCode, base.hashCode);
      expect(changed, isNot(base));
      expect(changed.copyWith().delayedSince, changed.delayedSince);
      expect(changed.copyWith(clearDelayedSince: true).delayedSince, isNull);
      expect(
        changed
            .copyWith(delayedSince: at, clearDelayedSince: true)
            .delayedSince,
        isNull,
      );
    });

    test('a history page knows whether more follow', () {
      RoutedSwapHistoryPage page(int number) => RoutedSwapHistoryPage(
        entries: [_snapshot()],
        total: 3,
        pageNumber: number,
        totalPages: 3,
      );
      expect(page(1).hasMore, isTrue);
      expect(page(3).hasMore, isFalse);
      expect(page(1), page(1));
      expect(page(1).hashCode, page(1).hashCode);
      expect(page(1), isNot(page(2)));
    });
  });

  group('exceptions', () {
    test('a refused cancel names the swap, the reason and the phase', () {
      const broadcast = RoutedSwapNotCancellableException(
        'u-1',
        RoutedSwapPhase.sending,
      );
      expect(broadcast.refusal, RoutedSwapCancelRefusal.alreadyBroadcast);
      expect(
        broadcast.toString(),
        'Routed swap u-1 cannot be cancelled (alreadyBroadcast, '
        'phase sending).',
      );
      const gone = RoutedSwapNotCancellableException(
        'u-2',
        RoutedSwapPhase.bridging,
        refusal: RoutedSwapCancelRefusal.notAddressable,
      );
      expect(
        gone.toString(),
        'Routed swap u-2 cannot be cancelled (notAddressable, '
        'phase bridging).',
      );
    });

    test('unconfirmed and missing swaps say so and keep the cause', () {
      final cause = StateError('dropped');
      final cancel = RoutedSwapCancelUnconfirmedException('u-1', cause);
      expect(cancel.uuid, 'u-1');
      expect(cancel.cause, same(cause));
      expect(
        cancel.toString(),
        'Could not confirm cancelling routed swap u-1.',
      );

      final start = RoutedSwapStartUnconfirmedException(cause);
      expect(start.taskId, isNull);
      expect(start.cause, same(cause));
      expect(
        start.toString(),
        'Could not confirm whether the routed swap started.',
      );
      expect(RoutedSwapStartUnconfirmedException(cause, taskId: 4).taskId, 4);

      const missing = RoutedSwapNotFoundException('u-3');
      expect(missing.uuid, 'u-3');
      expect(missing.toString(), 'No routed swap found for u-3.');
    });
  });
}
