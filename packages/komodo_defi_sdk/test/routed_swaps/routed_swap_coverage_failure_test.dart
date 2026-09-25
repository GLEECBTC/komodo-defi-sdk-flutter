import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:fake_async/fake_async.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:test/test.dart';

import 'routed_swap_coverage_fakes.dart';

/// Reads [entry] through a manager that never watched the swap live.
Future<RoutedSwapProgress> recorded(JsonMap entry) async {
  final kdf = ScriptedKdf()
    ..always('routed_swap::history', (_) => historyAnswer([entry]));
  return (await managerFor(kdf).history()).entries.single;
}

Future<RoutedSwapFailure> failureOf(
  String errorType, {
  Object? data,
  String message = 'failed',
  List<String> approvals = const [],
}) async => (await recorded(
  entryJson(
    failedWith(uuidOf(1), errorType, data: data, message: message),
    approvals: approvals,
  ),
)).failure!;

void main() {
  group('failure classification from the durable record', () {
    test('each failure says whether funds moved and what to offer', () async {
      const approved = ['0xapprove'];
      const cases = [
        (
          'ApprovalFailed',
          {'reason': 'approval_broadcast_failed'},
          approved,
          RoutedSwapFailureKind.approvalFailed,
          RoutedSwapFundsMovement.feesOnly,
          RoutedSwapRetryPolicy.retry,
        ),
        (
          'ApprovalFailed',
          {'reason': 'allowance_reset_not_confirmed'},
          <String>[],
          RoutedSwapFailureKind.approvalFailed,
          RoutedSwapFundsMovement.feesOnly,
          RoutedSwapRetryPolicy.retry,
        ),
        (
          'SigningRejected',
          {'reason': 'user_rejected'},
          approved,
          RoutedSwapFailureKind.signingRejected,
          RoutedSwapFundsMovement.feesOnly,
          RoutedSwapRetryPolicy.retry,
        ),
        (
          'SigningRejected',
          {'reason': 'timeout'},
          <String>[],
          RoutedSwapFailureKind.signingRejected,
          RoutedSwapFundsMovement.uncertain,
          RoutedSwapRetryPolicy.wait,
        ),
        (
          'InternalError',
          {'message': 'handoff lost'},
          <String>[],
          RoutedSwapFailureKind.internalError,
          RoutedSwapFundsMovement.uncertain,
          RoutedSwapRetryPolicy.contactSupport,
        ),
        (
          'TransportError',
          {'message': 'unreachable'},
          approved,
          RoutedSwapFailureKind.internalError,
          RoutedSwapFundsMovement.feesOnly,
          RoutedSwapRetryPolicy.retry,
        ),
        (
          'SwapTxFailed',
          {'reason': 'reorged'},
          <String>[],
          RoutedSwapFailureKind.swapTransactionFailed,
          RoutedSwapFundsMovement.uncertain,
          RoutedSwapRetryPolicy.wait,
        ),
        (
          'TaskCancelled',
          null,
          approved,
          RoutedSwapFailureKind.cancelled,
          RoutedSwapFundsMovement.feesOnly,
          RoutedSwapRetryPolicy.retry,
        ),
        (
          'RateLimited',
          <String, dynamic>{},
          approved,
          RoutedSwapFailureKind.quoteUnavailable,
          RoutedSwapFundsMovement.feesOnly,
          RoutedSwapRetryPolicy.retry,
        ),
        (
          'PreflightRejected',
          {'check': 'oracle_price'},
          <String>[],
          RoutedSwapFailureKind.preflightRejected,
          RoutedSwapFundsMovement.none,
          RoutedSwapRetryPolicy.contactSupport,
        ),
        (
          'LiquidityVanished',
          {'extra': 1},
          <String>[],
          RoutedSwapFailureKind.unknown,
          RoutedSwapFundsMovement.uncertain,
          RoutedSwapRetryPolicy.contactSupport,
        ),
      ];
      for (final (type, data, approvals, kind, movement, policy) in cases) {
        final failure = await failureOf(type, data: data, approvals: approvals);
        final label = '$type $data $approvals';
        expect(failure.kind, kind, reason: label);
        expect(failure.fundsMovement, movement, reason: label);
        expect(failure.retryPolicy, policy, reason: label);
        expect(
          failure.fundsUntouched,
          movement == RoutedSwapFundsMovement.none,
          reason: label,
        );
      }
    });

    test(
      'an unrecognised signing reason never claims the funds stayed put',
      () async {
        final failure = await failureOf(
          'SigningRejected',
          data: {'reason': 'handoff_lost'},
        );
        expect(failure.fundsMovement, RoutedSwapFundsMovement.uncertain);
        expect(failure.retryPolicy, RoutedSwapRetryPolicy.wait);
      },
    );

    test('an unknown error type keeps its payload for support', () async {
      final failure = await failureOf(
        'LiquidityVanished',
        data: {'provider_request_id': 'req-9', 'extra': 1},
        message: 'liquidity vanished',
      );
      expect(failure.errorType, 'LiquidityVanished');
      expect(failure.message, 'liquidity vanished');
      expect(failure.details, {'provider_request_id': 'req-9', 'extra': 1});
      expect(failure.providerRequestId, 'req-9');
      expect(failure.isRetryable, isFalse);
    });

    test('unreadable amounts read as zero, or as no bound', () async {
      final short = await failureOf(
        'InsufficientBalance',
        data: {'coin': 'NEW', 'available': 'lots', 'required': ''},
      );
      expect(
        short.shortfall,
        RoutedSwapShortfall(
          ticker: 'NEW',
          available: Decimal.zero,
          required: Decimal.zero,
        ),
      );

      final bounds = await failureOf(
        'AmountOutOfBounds',
        data: {'param': 'amount', 'value': '0.1', 'min': 'n/a', 'max': '9'},
      );
      expect(bounds.bounds, RoutedSwapAmountBounds(min: null, max: d('9')));
    });

    test(
      'a re-priced route is offered only in coins the wallet knows',
      () async {
        final known = await failureOf(
          'QuoteWorsened',
          data: {'fresh_route': routeJson(toMin: '98')},
        );
        expect(known.kind, RoutedSwapFailureKind.priceMoved);
        expect(known.freshOffer!.from, usdc);
        expect(known.freshOffer!.to, usdt);
        expect(known.freshOffer!.guaranteedReceive, d('98'));
        expect(known.freshOffer!.order, isNull);

        final unknown = await failureOf(
          'QuoteWorsened',
          data: {'fresh_route': routeJson(from: 'NEW-ONE', to: 'NEW-TWO')},
        );
        expect(unknown.freshOffer, isNull);
        expect((await failureOf('QuoteWorsened')).freshOffer, isNull);
      },
    );

    test('a bridge failure puts its evidence on the snapshot', () async {
      final progress = await recorded(
        entryJson(
          failedWith(
            uuidOf(1),
            'BridgeFailed',
            data: {
              'source_tx_hash': '0xsource',
              'provider_explorer_url': 'https://scan.li.fi/tx/1',
              'provider_request_id': 'req-1',
            },
          ),
        ),
      );
      expect(progress.phase, RoutedSwapPhase.failed);
      expect(progress.sourceTxHash, '0xsource');
      expect(progress.explorerUrl, 'https://scan.li.fi/tx/1');
      expect(progress.failure!.providerRequestId, 'req-1');
      expect(progress.failure!.fundsMovement, RoutedSwapFundsMovement.sent);
    });
  });

  group('snapshots from the durable record', () {
    test('blank or unreadable numbers still map', () async {
      final progress = await recorded(
        entryJson(
          completed(uuidOf(2)),
          createdAt: 0,
          finishedAt: 1754784020,
          to: 'NEW-TWO',
          amount: 'lots',
          minimum: 'n/a',
          gasSpent: const [
            {'tx_hash': '', 'coin': 'ETH', 'amount': 'x'},
            {'tx_hash': '0xa', 'coin': 'ETH', 'amount': '0.001'},
          ],
          totalGasSpent: const [
            {'coin': 'NEW', 'amount': '1'},
          ],
        ),
      );

      expect(progress.createdAt, isNull);
      expect(
        progress.updatedAt,
        DateTime.fromMillisecondsSinceEpoch(1754784010000, isUtc: true),
      );
      expect(
        progress.finishedAt,
        DateTime.fromMillisecondsSinceEpoch(1754784020000, isUtc: true),
      );
      expect(
        progress.requested,
        RoutedSwapRequest(
          fromTicker: 'USDC-ERC20',
          toTicker: 'NEW-TWO',
          from: usdc,
          amount: Decimal.zero,
        ),
      );
      expect(progress.minToAmountAccepted, isNull);
      expect(progress.gasSpent, [
        RoutedSwapGasPaid(ticker: 'ETH', assetId: eth, amount: Decimal.zero),
        RoutedSwapGasPaid(
          txHash: '0xa',
          ticker: 'ETH',
          assetId: eth,
          amount: d('0.001'),
        ),
      ]);
      expect(progress.totalGasSpent, [
        RoutedSwapGasPaid(ticker: 'NEW', amount: d('1')),
      ]);
    });

    test('an in-flight record maps detail, duration and approvals', () async {
      final approving = await recorded(
        entryJson(
          inProgress(
            uuidOf(3),
            'Approving',
            route: routeJson(),
            approveTxHash: '0xexact',
            substatus: 'WAIT_APPROVAL',
          ),
          approvals: const ['0xreset', '0xexact'],
        ),
      );
      expect(approving.phase, RoutedSwapPhase.approving);
      expect(approving.canCancel, isFalse);
      expect(approving.approvalTxHashes, ['0xreset', '0xexact']);
      expect(approving.approvalTxHash, '0xexact');
      expect(approving.providerStatusDetail, 'WAIT_APPROVAL');
      expect(approving.estimatedDuration, const Duration(seconds: 95));
      expect(approving.executedOffer!.from, usdc);
      expect(approving.offer, same(approving.executedOffer));

      final tracking = await recorded(
        entryJson(
          inProgress(
            uuidOf(3),
            'TrackingBridge',
            route: routeJson(from: 'NEW-ONE'),
            stage: 'destination_pending',
            substatus: 'WAIT_DESTINATION_TRANSACTION',
            substatusMessage: 'Waiting for the destination chain',
            durationS: 40,
          ),
        ),
      );
      expect(tracking.bridgeStage, RoutedSwapBridgeStage.destinationPending);
      expect(
        tracking.providerStatusDetail,
        'Waiting for the destination chain',
      );
      expect(tracking.estimatedDuration, const Duration(seconds: 40));
      expect(tracking.executedOffer, isNull);
      expect(tracking.offer, isNull);
    });
  });

  group('live snapshots', () {
    test('a state this build does not know cannot be cancelled', () {
      fakeAsync((async) {
        final kdf = ScriptedKdf();
        final manager = managerFor(kdf);
        final handle = startSwap(
          async,
          kdf,
          manager,
          first: inProgress(uuidOf(4), 'Rebalancing'),
        );

        expect(handle.latest.phase, RoutedSwapPhase.unknown);
        expect(handle.latest.rawState, 'Rebalancing');
        expect(handle.latest.canCancel, isFalse);
        expect(handle.latest.isTerminal, isFalse);
        expect(
          thrownBy(async, handle.cancel()),
          isA<RoutedSwapNotCancellableException>()
              .having(
                (e) => e.refusal,
                'refusal',
                RoutedSwapCancelRefusal.alreadyBroadcast,
              )
              .having((e) => e.phase, 'phase', RoutedSwapPhase.unknown),
        );
        expect(kdf.calls('task::routed_swap::cancel'), 0);
        unawaited(manager.dispose());
        async.flushMicrotasks();
      });
    });

    test('an unknown terminal error ends the swap and releases the task', () {
      fakeAsync((async) {
        final uuid = uuidOf(5);
        final kdf = ScriptedKdf()
          ..always(
            'task::routed_swap::status',
            (_) =>
                ok(failedWith(uuid, 'LiquidityVanished', data: {'extra': 1})),
          )
          ..always('routed_swap::history', (_) => historyAnswer(const []));
        final manager = managerFor(kdf);
        final handle = startSwap(
          async,
          kdf,
          manager,
          first: inProgress(uuid, 'FetchingQuote'),
        );
        async.elapse(const Duration(seconds: 3));

        final result = awaited(async, handle.result);
        expect(result.failure!.kind, RoutedSwapFailureKind.unknown);
        expect(
          result.failure!.retryPolicy,
          RoutedSwapRetryPolicy.contactSupport,
        );
        expect(kdf.paramsFor('task::routed_swap::status').last, {
          'task_id': 1,
          'forget_if_finished': true,
        });
        unawaited(manager.dispose());
        async.flushMicrotasks();
      });
    });
  });
}
