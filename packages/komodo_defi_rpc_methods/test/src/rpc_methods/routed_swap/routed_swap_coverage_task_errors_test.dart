import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:test/test.dart';

RoutedSwapTaskError _parse(String type, [JsonMap data = const {}]) =>
    RoutedSwapTaskError.parse(type, data);

const JsonMap _freshRoute = {
  'from': {'coin': 'USDT-ETH', 'amount': '1'},
  'to': {'coin': 'USDC-POLYGON', 'amount': '0.99', 'amount_min': '0.98'},
  'tool': {'key': 'across', 'name': 'Across V4'},
  'kind': 'cross_chain',
};

void main() {
  group('RoutedSwapTaskError.parse', () {
    test('QuoteWorsened carries the re-priced route when there is one', () {
      final worsened =
          _parse('QuoteWorsened', {'fresh_route': _freshRoute})
              as RoutedSwapQuoteWorsenedError;
      expect(worsened.freshRoute!.toMinimum.amount, '0.98');
      expect(worsened.freshRoute!.provider, 'lifi');
      expect(worsened.errorType, 'QuoteWorsened');
      expect(worsened.isPreBroadcast, isTrue);

      final bare = _parse('QuoteWorsened') as RoutedSwapQuoteWorsenedError;
      expect(bare.freshRoute, isNull);
    });

    test('InsufficientBalance names the coin and both amounts', () {
      final short =
          _parse('InsufficientBalance', {
                'coin': 'ETH',
                'available': '0.001',
                'required': '0.0129',
              })
              as RoutedSwapInsufficientBalanceError;
      expect(
        [short.coin, short.available, short.required],
        ['ETH', '0.001', '0.0129'],
      );
      expect(short.errorType, 'InsufficientBalance');
      expect(short.isPreBroadcast, isTrue);

      final blank =
          _parse('InsufficientBalance') as RoutedSwapInsufficientBalanceError;
      expect([blank.coin, blank.available, blank.required], ['', '', '']);
    });

    test('ApprovalFailed reads every reason, and a new one leniently', () {
      for (final reason in RoutedSwapApprovalFailureReason.values) {
        final failed =
            _parse('ApprovalFailed', {'reason': reason.wire})
                as RoutedSwapApprovalFailedError;
        expect(failed.reason, reason);
        expect(failed.errorType, 'ApprovalFailed');
        expect(failed.isPreBroadcast, isTrue);
      }
      final later =
          _parse('ApprovalFailed', {'reason': 'gas_spike'})
              as RoutedSwapApprovalFailedError;
      expect(later.reason, RoutedSwapApprovalFailureReason.unknown);
      final absent = _parse('ApprovalFailed') as RoutedSwapApprovalFailedError;
      expect(absent.reason, RoutedSwapApprovalFailureReason.unknown);
    });

    test('SwapTxFailed reads the source hash and whether it may confirm', () {
      final reverted =
          _parse('SwapTxFailed', {
                'source_tx_hash': '0xsource',
                'tx_hash': '0xlegacy',
                'reason': 'source_transaction_reverted',
              })
              as RoutedSwapTxFailedError;
      expect(reverted.sourceTxHash, '0xsource');
      expect(reverted.mayStillConfirm, isFalse);
      expect(reverted.errorType, 'SwapTxFailed');
      expect(reverted.isPreBroadcast, isFalse);

      final pending =
          _parse('SwapTxFailed', {
                'tx_hash': '0xlegacy',
                'reason': 'source_transaction_not_confirmed',
              })
              as RoutedSwapTxFailedError;
      expect(pending.sourceTxHash, '0xlegacy');
      expect(pending.mayStillConfirm, isTrue);

      final unknown = _parse('SwapTxFailed') as RoutedSwapTxFailedError;
      expect(unknown.sourceTxHash, isNull);
      expect(unknown.reason, RoutedSwapTxFailureReason.unknown);
      expect(unknown.mayStillConfirm, isTrue);
    });

    test('SigningRejected is pre-broadcast unless the wallet timed out', () {
      bool preBroadcast(String reason) =>
          _parse('SigningRejected', {'reason': reason}).isPreBroadcast;
      expect(preBroadcast('user_rejected'), isTrue);
      expect(preBroadcast('unsupported_method'), isTrue);
      expect(preBroadcast('timeout'), isFalse);

      final declined =
          _parse('SigningRejected', {'reason': 'user_rejected'})
              as RoutedSwapSigningRejectedError;
      expect(declined.reason, RoutedSwapSigningRejectionReason.userRejected);
      expect(declined.errorType, 'SigningRejected');
    });

    test(
      'an unrecognised signing reason is not proof nothing was broadcast',
      () {
        final later = _parse('SigningRejected', {'reason': 'handoff_lost'});
        expect(later.isPreBroadcast, isFalse);
      },
    );

    test('BridgeFailed keeps every passthrough and the source hash', () {
      final bridge =
          _parse('BridgeFailed', {
                'tx_hash': '0xlegacy',
                'substatus': 'REFUND_FAILED',
                'substatus_message': 'Manual support is required',
                'provider_explorer_url': 'https://scan.li.fi/tx/1',
                'provider_request_id': 'req-1',
              })
              as RoutedSwapBridgeFailedError;
      expect(bridge.sourceTxHash, '0xlegacy');
      expect(bridge.substatus, 'REFUND_FAILED');
      expect(bridge.substatusMessage, 'Manual support is required');
      expect(bridge.providerExplorerUrl, 'https://scan.li.fi/tx/1');
      expect(bridge.providerRequestId, 'req-1');
      expect(bridge.errorType, 'BridgeFailed');
      expect(bridge.isPreBroadcast, isFalse);

      final preferred =
          _parse('BridgeFailed', {
                'source_tx_hash': '0xsource',
                'tx_hash': '0xlegacy',
              })
              as RoutedSwapBridgeFailedError;
      expect(preferred.sourceTxHash, '0xsource');
      expect(preferred.substatus, isNull);
    });

    test('PreflightRejected reads every check; only simulation retries', () {
      for (final check in RoutedSwapPreflightCheck.values) {
        final rejected =
            _parse('PreflightRejected', {'check': check.wire})
                as RoutedSwapPreflightRejectedError;
        expect(rejected.check, check);
        expect(rejected.errorType, 'PreflightRejected');
        expect(rejected.isPreBroadcast, isTrue);
      }
      final later =
          _parse('PreflightRejected', {'check': 'oracle_price'})
              as RoutedSwapPreflightRejectedError;
      expect(later.check, RoutedSwapPreflightCheck.unknown);
    });

    test('fresh-quote failures carry reasons, request id and bounds', () {
      final noRoute =
          _parse('NoRouteFound', {
                'reasons': ['no liquidity', 7, 'amount too low (hop)'],
                'provider_request_id': 'req-1',
              })
              as RoutedSwapNoRouteTaskError;
      expect(noRoute.reasons, ['no liquidity', 'amount too low (hop)']);
      expect(noRoute.providerRequestId, 'req-1');
      expect(noRoute.errorType, 'NoRouteFound');

      final limited =
          _parse('RateLimited', {'provider_request_id': 'req-2'})
              as RoutedSwapRateLimitedTaskError;
      expect(limited.providerRequestId, 'req-2');
      expect(limited.errorType, 'RateLimited');

      final provider =
          _parse('ProviderApiError', {'message': 'upstream'})
              as RoutedSwapProviderTaskError;
      expect(provider.message, 'upstream');
      expect(provider.providerRequestId, isNull);
      expect(provider.errorType, 'ProviderApiError');

      final bounds =
          _parse('AmountOutOfBounds', {
                'param': 'amount',
                'value': '0.1',
                'min': '1',
                'max': '9',
              })
              as RoutedSwapAmountOutOfBoundsTaskError;
      expect(
        [bounds.param, bounds.value, bounds.min, bounds.max],
        ['amount', '0.1', '1', '9'],
      );
      expect(bounds.errorType, 'AmountOutOfBounds');

      for (final error in [noRoute, limited, provider, bounds]) {
        expect(error.isPreBroadcast, isTrue, reason: error.errorType);
      }
    });

    test('restart, cancellation, internal and transport failures', () {
      final aborted = _parse('AbortedOnRestart');
      expect(aborted, same(const RoutedSwapAbortedOnRestartError()));
      expect(aborted.errorType, 'AbortedOnRestart');
      expect(aborted.isPreBroadcast, isTrue);

      final cancelled = _parse('TaskCancelled');
      expect(cancelled, same(const RoutedSwapTaskCancelledError()));
      expect(cancelled.errorType, 'TaskCancelled');
      expect(cancelled.isPreBroadcast, isTrue);
      expect(cancelled, isNot(aborted));

      final internal =
          _parse('InternalError', {'message': 'handoff lost'})
              as RoutedSwapInternalTaskError;
      expect(internal.message, 'handoff lost');
      expect(internal.errorType, 'InternalError');
      expect(internal.isPreBroadcast, isFalse);

      final transport =
          _parse('TransportError', {'message': 'unreachable'})
              as RoutedSwapTransportTaskError;
      expect(transport.message, 'unreachable');
      expect(transport.errorType, 'TransportError');
      expect(transport.isPreBroadcast, isTrue);
    });

    test(
      'an unknown error type keeps its payload and is not pre-broadcast',
      () {
        final unknown =
            _parse('LiquidityVanished', {
                  'provider_request_id': 'req-9',
                  'extra': 1,
                })
                as RoutedSwapUnknownTaskError;
        expect(unknown.errorType, 'LiquidityVanished');
        expect(unknown.data, {'provider_request_id': 'req-9', 'extra': 1});
        expect(unknown.providerRequestId, 'req-9');
        expect(unknown.isPreBroadcast, isFalse);

        expect(_parse('LiquidityVanished').providerRequestId, isNull);
        expect(const RoutedSwapUnknownTaskError(errorType: 'X').data, isEmpty);
      },
    );

    test('only provider-originated errors carry a support request id', () {
      const data = {'provider_request_id': 'req-1'};
      const cases = <(String, String?)>[
        ('NoRouteFound', 'req-1'),
        ('RateLimited', 'req-1'),
        ('ProviderApiError', 'req-1'),
        ('BridgeFailed', 'req-1'),
        ('Mystery', 'req-1'),
        ('QuoteWorsened', null),
        ('InsufficientBalance', null),
        ('SwapTxFailed', null),
        ('InternalError', null),
        ('TaskCancelled', null),
      ];
      for (final (type, id) in cases) {
        expect(_parse(type, data).providerRequestId, id, reason: type);
      }
    });
  });

  group('value semantics', () {
    test('equal payloads are equal errors; any field change is not', () {
      const samples = <(String, JsonMap, JsonMap)>[
        ('QuoteWorsened', {'fresh_route': _freshRoute}, {}),
        (
          'InsufficientBalance',
          {'coin': 'ETH', 'available': '1', 'required': '2'},
          {'coin': 'ETH', 'available': '1', 'required': '3'},
        ),
        (
          'ApprovalFailed',
          {'reason': 'approval_broadcast_failed'},
          {'reason': 'approval_transaction_failed'},
        ),
        ('SwapTxFailed', {'source_tx_hash': '0x1'}, {'source_tx_hash': '0x2'}),
        ('SigningRejected', {'reason': 'user_rejected'}, {'reason': 'timeout'}),
        ('BridgeFailed', {'substatus': 'A'}, {'substatus': 'B'}),
        ('PreflightRejected', {'check': 'simulation'}, {'check': 'value_cap'}),
        (
          'NoRouteFound',
          {
            'reasons': ['a'],
          },
          {
            'reasons': ['b'],
          },
        ),
        (
          'RateLimited',
          {'provider_request_id': 'r1'},
          {'provider_request_id': 'r2'},
        ),
        ('ProviderApiError', {'message': 'a'}, {'message': 'b'}),
        (
          'AmountOutOfBounds',
          {'param': 'amount', 'min': '1', 'max': '2'},
          {'param': 'amount', 'min': '1', 'max': '3'},
        ),
        ('InternalError', {'message': 'a'}, {'message': 'b'}),
        ('TransportError', {'message': 'a'}, {'message': 'b'}),
        ('Mystery', {'x': 1}, {'x': 2}),
      ];
      for (final (type, a, b) in samples) {
        expect(_parse(type, a), _parse(type, a), reason: type);
        expect(_parse(type, a).hashCode, _parse(type, a).hashCode);
        expect(_parse(type, a), isNot(_parse(type, b)), reason: type);
      }
      for (final type in ['AbortedOnRestart', 'TaskCancelled']) {
        expect(_parse(type).hashCode, _parse(type).hashCode, reason: type);
        expect(_parse(type).props, isEmpty);
      }
    });
  });

  group('reason enums', () {
    test('each wire value parses back; anything else is unknown', () {
      for (final reason in RoutedSwapApprovalFailureReason.values) {
        expect(RoutedSwapApprovalFailureReason.parse(reason.wire), reason);
      }
      for (final reason in RoutedSwapTxFailureReason.values) {
        expect(RoutedSwapTxFailureReason.parse(reason.wire), reason);
      }
      for (final reason in RoutedSwapSigningRejectionReason.values) {
        expect(RoutedSwapSigningRejectionReason.parse(reason.wire), reason);
      }
      for (final check in RoutedSwapPreflightCheck.values) {
        expect(RoutedSwapPreflightCheck.parse(check.wire), check);
      }
      for (final value in [null, 'added_later']) {
        expect(
          RoutedSwapApprovalFailureReason.parse(value),
          RoutedSwapApprovalFailureReason.unknown,
        );
        expect(
          RoutedSwapTxFailureReason.parse(value),
          RoutedSwapTxFailureReason.unknown,
        );
        expect(
          RoutedSwapSigningRejectionReason.parse(value),
          RoutedSwapSigningRejectionReason.unknown,
        );
        expect(
          RoutedSwapPreflightCheck.parse(value),
          RoutedSwapPreflightCheck.unknown,
        );
      }
    });

    test('only a failed simulation is worth retrying as is', () {
      const retryable = {RoutedSwapPreflightCheck.simulation};
      const requotable = {
        RoutedSwapPreflightCheck.simulation,
        RoutedSwapPreflightCheck.valueCap,
        RoutedSwapPreflightCheck.amountBounds,
        RoutedSwapPreflightCheck.gasBounds,
      };
      for (final check in RoutedSwapPreflightCheck.values) {
        expect(check.isRetryable, retryable.contains(check), reason: '$check');
        expect(
          check.mayPassOnRequote,
          requotable.contains(check),
          reason: '$check',
        );
      }
    });
  });
}
