import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:test/test.dart';

const String _uuid = '0d4dbd0c-5a4e-4b7f-9c1d-2e3f4a5b6c7d';

const JsonMap _route = {
  'provider': 'lifi',
  'from': {'coin': 'ETH', 'amount': '1'},
  'to': {'coin': 'USDC-POLYGON', 'amount': '2', 'amount_min': '1.9'},
  'tool': {'key': 'across', 'name': 'Across V4'},
  'kind': 'cross_chain',
};

RoutedSwapStatus _parse(String status, JsonMap details) =>
    RoutedSwapStatus.parse(status, details);

JsonMap _okDetails({
  String outcome = 'completed',
  String? partialReason,
  String? destTxHash = '0xdest',
}) => {
  'uuid': _uuid,
  'executed_route': _route,
  'outcome': outcome,
  'partial_reason': ?partialReason,
  'received': {'coin': 'USDC-POLYGON', 'amount': '1.95'},
  'source_tx_hash': '0xsource',
  'dest_tx_hash': ?destTxHash,
  'provider_explorer_url': 'https://scan.li.fi/tx/1',
};

void main() {
  group('an in-progress snapshot', () {
    test('reads every field while tracking the bridge', () {
      final status =
          _parse('InProgress', {
                'uuid': _uuid,
                'provider': 'lifi',
                'state': 'TrackingBridge',
                'executed_route': _route,
                'approve_tx_hash': '0xapprove',
                'source_tx_hash': '0xsource',
                'stage': 'refund_pending',
                'substatus': 'WAIT_SOURCE_REFUND',
                'substatus_message': 'Refund in progress',
                'provider_explorer_url': 'https://scan.li.fi/tx/1',
                'execution_duration_s': 31,
                'action_url': 'https://li.fi/act',
              })
              as RoutedSwapInProgress;

      expect(status.uuid, _uuid);
      expect(status.provider, 'lifi');
      expect(status.state, RoutedSwapState.trackingBridge);
      expect(status.rawState, 'TrackingBridge');
      expect(status.executedRoute!.tool.key, 'across');
      expect(status.approveTxHash, '0xapprove');
      expect(status.sourceTxHash, '0xsource');
      expect(status.stage, RoutedSwapBridgeStage.refundPending);
      expect(status.rawStage, 'refund_pending');
      expect(status.substatus, 'WAIT_SOURCE_REFUND');
      expect(status.substatusMessage, 'Refund in progress');
      expect(status.providerExplorerUrl, 'https://scan.li.fi/tx/1');
      expect(status.executionDurationS, 31);
      expect(status.actionUrl, 'https://li.fi/act');
      expect(status.isTerminal, isFalse);
    });

    test('keeps an unknown state and stage raw, and reads tx_hash', () {
      final status =
          _parse('InProgress', {
                'uuid': _uuid,
                'state': 'Rebalancing',
                'tx_hash': '0xlegacy',
                'stage': 'teleporting',
              })
              as RoutedSwapInProgress;

      expect(status.provider, 'lifi');
      expect(status.state, RoutedSwapState.unknown);
      expect(status.rawState, 'Rebalancing');
      expect(status.sourceTxHash, '0xlegacy');
      expect(status.stage, RoutedSwapBridgeStage.unknown);
      expect(status.rawStage, 'teleporting');
      expect(status.executedRoute, isNull);
    });

    test('has no stage at all until the engine reports one', () {
      final status =
          _parse('InProgress', {'uuid': _uuid, 'state': 'Signing'})
              as RoutedSwapInProgress;
      expect(status.stage, isNull);
      expect(status.rawStage, isNull);
      expect(status.approveTxHash, isNull);
      expect(status.sourceTxHash, isNull);
      expect(status.executionDurationS, isNull);
    });

    test('any status other than Ok or Error is read as in progress', () {
      expect(
        _parse('UserActionRequired', {'uuid': _uuid, 'state': 'Signing'}),
        isA<RoutedSwapInProgress>(),
      );
    });

    test('a snapshot without its uuid or state is unreadable', () {
      expect(
        () => _parse('InProgress', {'state': 'Signing'}),
        throwsArgumentError,
      );
      expect(() => _parse('InProgress', {'uuid': _uuid}), throwsArgumentError);
    });
  });

  group('a terminal Ok', () {
    test('reads the outcome, what arrived and both hashes', () {
      final status = _parse('Ok', _okDetails()) as RoutedSwapFinished;
      expect(status.outcome, RoutedSwapOutcome.completed);
      expect(status.partialReason, isNull);
      expect(status.received.coin, 'USDC-POLYGON');
      expect(status.received.amount, '1.95');
      expect(status.sourceTxHash, '0xsource');
      expect(status.destTxHash, '0xdest');
      expect(status.providerExplorerUrl, 'https://scan.li.fi/tx/1');
      expect(status.executedRoute!.toMinimum.amount, '1.9');
      expect(status.isTerminal, isTrue);
    });

    test('an outcome this build does not know is never a success', () {
      final status =
          _parse('Ok', _okDetails(outcome: 'teleported')) as RoutedSwapFinished;
      expect(status.outcome, RoutedSwapOutcome.unknown);
      expect(status.outcome.isSuccess, isFalse);
    });

    test('a partial reason is read leniently when present', () {
      RoutedSwapPartialReason? reason(String? wire) =>
          (_parse('Ok', _okDetails(outcome: 'partial', partialReason: wire))
                  as RoutedSwapFinished)
              .partialReason;
      expect(reason('below_minimum'), RoutedSwapPartialReason.belowMinimum);
      expect(
        reason('intermediate_token'),
        RoutedSwapPartialReason.intermediateToken,
      );
      expect(reason('rounding'), RoutedSwapPartialReason.unknown);
      expect(reason(null), isNull);
    });

    test('a received provider symbol is not a wallet asset', () {
      final status =
          _parse('Ok', {
                ..._okDetails(outcome: 'partial', destTxHash: null),
                'received': {'symbol': 'axlUSDC', 'amount': '1.9'},
              })
              as RoutedSwapFinished;
      expect(status.received.isKnownAsset, isFalse);
      expect(status.received.label, 'axlUSDC');
      expect(status.destTxHash, isNull);
    });
  });

  group('a terminal Error', () {
    test('keeps the error type and message beside the typed payload', () {
      final status =
          _parse('Error', {
                'uuid': _uuid,
                'executed_route': _route,
                'error_type': 'SwapTxFailed',
                'error': 'Source transaction reverted',
                'error_data': {
                  'source_tx_hash': '0xsource',
                  'reason': 'source_transaction_reverted',
                },
              })
              as RoutedSwapErrored;
      expect(status.errorType, 'SwapTxFailed');
      expect(status.message, 'Source transaction reverted');
      expect(
        status.error,
        isA<RoutedSwapTxFailedError>().having(
          (e) => e.sourceTxHash,
          'sourceTxHash',
          '0xsource',
        ),
      );
      expect(status.isTerminal, isTrue);
    });

    test('a missing message is the error type; bad data reads empty', () {
      final bare =
          _parse('Error', {
                'uuid': _uuid,
                'error_type': 'InternalError',
                'error_data': 'handoff lost',
              })
              as RoutedSwapErrored;
      expect(bare.message, 'InternalError');
      expect((bare.error as RoutedSwapInternalTaskError).message, isEmpty);
    });

    test('a missing error type is an unknown error with no name', () {
      final status = _parse('Error', {'uuid': _uuid}) as RoutedSwapErrored;
      expect(status.errorType, isEmpty);
      expect(status.message, isEmpty);
      expect(status.error, isA<RoutedSwapUnknownTaskError>());
      expect(status.error.errorType, isEmpty);
    });
  });

  group('value semantics', () {
    test('equal snapshots are equal; any changed field is not', () {
      final tracking = {
        'uuid': _uuid,
        'state': 'TrackingBridge',
        'stage': 'bridging',
        'executed_route': _route,
      };
      final a = _parse('InProgress', tracking);
      expect(a, _parse('InProgress', tracking));
      expect(a.hashCode, _parse('InProgress', tracking).hashCode);
      expect(a, isNot(_parse('InProgress', {...tracking, 'uuid': 'other'})));
      expect(
        a,
        isNot(_parse('InProgress', {...tracking, 'stage': 'refund_pending'})),
      );
      expect(a, isNot(_parse('InProgress', {...tracking, 'provider': 'x'})));

      final ok = _parse('Ok', _okDetails());
      expect(ok, _parse('Ok', _okDetails()));
      expect(ok.hashCode, _parse('Ok', _okDetails()).hashCode);
      expect(ok, isNot(_parse('Ok', _okDetails(destTxHash: '0xother'))));

      final error = {'uuid': _uuid, 'error_type': 'TaskCancelled'};
      final errored = _parse('Error', error);
      expect(errored, _parse('Error', error));
      expect(errored.hashCode, _parse('Error', error).hashCode);
      expect(errored, isNot(_parse('Error', {...error, 'error': 'other'})));
      expect(errored, isNot(ok));
    });
  });

  group('wire enums', () {
    test('only states before Broadcasting can be cancelled', () {
      const preBroadcast = {
        RoutedSwapState.fetchingQuote,
        RoutedSwapState.checkingAllowance,
        RoutedSwapState.approving,
        RoutedSwapState.signing,
      };
      for (final state in RoutedSwapState.values) {
        expect(RoutedSwapState.parse(state.wire), state);
        expect(state.isPostBroadcast, !preBroadcast.contains(state));
        expect(state.isCancellable, preBroadcast.contains(state));
      }
      expect(RoutedSwapState.parse('Rebalancing'), RoutedSwapState.unknown);
      expect(RoutedSwapState.unknown.isCancellable, isFalse);
    });

    test('a missing or new bridge stage is unknown', () {
      for (final stage in RoutedSwapBridgeStage.values) {
        expect(RoutedSwapBridgeStage.parse(stage.wire), stage);
      }
      expect(RoutedSwapBridgeStage.parse(null), RoutedSwapBridgeStage.unknown);
      expect(
        RoutedSwapBridgeStage.parse('teleporting'),
        RoutedSwapBridgeStage.unknown,
      );
    });

    test('only a completed outcome is a success', () {
      for (final outcome in RoutedSwapOutcome.values) {
        expect(RoutedSwapOutcome.parse(outcome.wire), outcome);
        expect(outcome.isSuccess, outcome == RoutedSwapOutcome.completed);
      }
      expect(RoutedSwapOutcome.parse('teleported'), RoutedSwapOutcome.unknown);
    });

    test('partial reasons and route kinds parse leniently', () {
      for (final reason in RoutedSwapPartialReason.values) {
        expect(RoutedSwapPartialReason.parse(reason.wire), reason);
      }
      expect(
        RoutedSwapPartialReason.parse(null),
        RoutedSwapPartialReason.unknown,
      );
      for (final kind in RoutedSwapRouteKind.values) {
        expect(RoutedSwapRouteKind.parse(kind.wire), kind);
      }
      expect(
        RoutedSwapRouteKind.parse('multi_hop'),
        RoutedSwapRouteKind.unknown,
      );
    });
  });

  group('task::routed_swap::status', () {
    test('sends the task id and does not forget unless asked', () {
      final json = RoutedSwapStatusRequest(rpcPass: 'pw', taskId: 3).toJson();
      expect(json['method'], 'task::routed_swap::status');
      expect(json['mmrpc'], '2.0');
      expect(json['rpc_pass'], 'pw');
      expect(json['params'], {'task_id': 3, 'forget_if_finished': false});

      final forget = RoutedSwapStatusRequest(
        rpcPass: '',
        taskId: 3,
        forgetIfFinished: true,
      ).toJson();
      expect(forget.containsKey('rpc_pass'), isFalse);
      expect(forget['params'], {'task_id': 3, 'forget_if_finished': true});
    });

    test('only an Error envelope with details is a response', () {
      final request = RoutedSwapStatusRequest(rpcPass: '', taskId: 3);
      final errored = request.parseResponseJson({
        'mmrpc': '2.0',
        'result': {
          'status': 'Error',
          'details': {'uuid': _uuid, 'error_type': 'TaskCancelled'},
        },
      });
      expect(errored.details, isA<RoutedSwapErrored>());

      expect(
        () => request.parseResponseJson({
          'mmrpc': '2.0',
          'result': {'status': 'Error'},
        }),
        throwsA(isA<GeneralErrorResponse>()),
      );
    });

    test('the response summarises its snapshot by uuid', () {
      final response = RoutedSwapStatusResponse.parse({
        'result': {
          'status': 'InProgress',
          'details': {'uuid': _uuid, 'state': 'Signing'},
        },
      });
      expect(response.mmrpc, '2.0');
      expect(response.status, 'InProgress');
      expect(response.toJson(), {
        'mmrpc': '2.0',
        'result': {'status': 'InProgress', 'details': _uuid},
      });
    });
  });
}
