part of 'routed_swap_wire_golden_test.dart';

void _cases3() {
  group('task::routed_swap::status Error', () {
    rpc.RoutedSwapErrored errored(
      String errorType,
      String error,
      Object errorData, {
      bool withRoute = true,
    }) {
      final status =
          _status('Error', {
                'error': error,
                'error_path': 'swap_task',
                'error_trace': 'swap_task:1113]',
                'uuid': _uuid,
                'provider': 'lifi',
                if (withRoute) 'executed_route': _nativeRoute,
                'error_type': errorType,
                'error_data': errorData,
              })
              as rpc.RoutedSwapErrored;
      expect(status.uuid, _uuid);
      expect(status.provider, 'lifi');
      expect(status.errorType, errorType);
      expect(status.message, error);
      expect(status.executedRoute, withRoute ? isNotNull : isNull);
      return status;
    }

    test('QuoteWorsened: fresh route in error_data, no executed route', () {
      final status = errored(
        'QuoteWorsened',
        'Fresh route is below the accepted minimum',
        {'fresh_route': _nativeRoute},
        withRoute: false,
      );
      final error = status.error as rpc.RoutedSwapQuoteWorsenedError;
      expect(error.freshRoute, rpc.RoutedSwapRoute.fromJson(_nativeRoute));
      expect(error.isPreBroadcast, isTrue);
    });

    test('InsufficientBalance', () {
      final error =
          errored(
                'InsufficientBalance',
                'Insufficient ETH balance: available 0.5, required 1.00063',
                {'coin': 'ETH', 'available': '0.5', 'required': '1.00063'},
              ).error
              as rpc.RoutedSwapInsufficientBalanceError;
      expect(
        [error.coin, error.available, error.required],
        ['ETH', '0.5', '1.00063'],
      );
    });

    test('ApprovalFailed, for each reason', () {
      for (final reason in rpc.RoutedSwapApprovalFailureReason.values.where(
        (r) => r != rpc.RoutedSwapApprovalFailureReason.unknown,
      )) {
        final error =
            errored('ApprovalFailed', 'Token approval failed: ${reason.wire}', {
                  'reason': reason.wire,
                }).error
                as rpc.RoutedSwapApprovalFailedError;
        expect(error.reason, reason);
      }
    });

    test('SwapTxFailed names the source transaction', () {
      final reverted =
          errored(
                'SwapTxFailed',
                'Routed swap transaction $_sourceHash failed: '
                    'source_transaction_reverted',
                {
                  'source_tx_hash': _sourceHash,
                  'reason': 'source_transaction_reverted',
                },
              ).error
              as rpc.RoutedSwapTxFailedError;
      expect(reverted.sourceTxHash, _sourceHash);
      expect(reverted.mayStillConfirm, isFalse);

      final unconfirmed =
          errored(
                'SwapTxFailed',
                'Routed swap transaction $_sourceHash failed: '
                    'source_transaction_not_confirmed',
                {
                  'source_tx_hash': _sourceHash,
                  'reason': 'source_transaction_not_confirmed',
                },
              ).error
              as rpc.RoutedSwapTxFailedError;
      expect(unconfirmed.mayStillConfirm, isTrue);
    });

    test('SigningRejected: only a timeout may have broadcast', () {
      for (final reason in rpc.RoutedSwapSigningRejectionReason.values.where(
        (r) => r != rpc.RoutedSwapSigningRejectionReason.unknown,
      )) {
        final error =
            errored(
                  'SigningRejected',
                  'Wallet rejected the routed swap transaction: '
                      '${reason.wire}',
                  {'reason': reason.wire},
                ).error
                as rpc.RoutedSwapSigningRejectedError;
        expect(error.reason, reason);
        expect(
          error.isPreBroadcast,
          reason != rpc.RoutedSwapSigningRejectionReason.timeout,
        );
      }
    });

    test('BridgeFailed with absent optional fields omitted', () {
      // routed_swap_task_error_wire_omits_absent_optional_fields.
      final bare =
          errored(
                'BridgeFailed',
                'Routed swap bridge failed for transaction $_sourceHash',
                {'source_tx_hash': _sourceHash, 'substatus': 'UNKNOWN_ERROR'},
              ).error
              as rpc.RoutedSwapBridgeFailedError;
      expect(bare.substatus, 'UNKNOWN_ERROR');
      expect(bare.substatusMessage, isNull);
      expect(bare.providerExplorerUrl, isNull);
      expect(bare.providerRequestId, isNull);
      expect(bare.isPreBroadcast, isFalse);

      // The serializer supports every optional key.
      final full =
          errored(
                'BridgeFailed',
                'Routed swap bridge failed for transaction $_sourceHash',
                {
                  'source_tx_hash': _sourceHash,
                  'substatus': 'NOT_PROCESSABLE_REFUND_NEEDED',
                  'substatus_message': 'Manual support is required',
                  'provider_explorer_url': 'https://scan.li.fi/tx/1',
                  'provider_request_id': 'req-3',
                },
              ).error
              as rpc.RoutedSwapBridgeFailedError;
      expect(full.substatusMessage, 'Manual support is required');
      expect(full.providerExplorerUrl, 'https://scan.li.fi/tx/1');
      expect(full.providerRequestId, 'req-3');
    });

    test('PreflightRejected, for each check', () {
      for (final check in rpc.RoutedSwapPreflightCheck.values.where(
        (c) => c != rpc.RoutedSwapPreflightCheck.unknown,
      )) {
        final error =
            errored(
                  'PreflightRejected',
                  'Routed swap preflight rejected by the ${check.wire} check',
                  {'check': check.wire},
                ).error
                as rpc.RoutedSwapPreflightRejectedError;
        expect(error.check, check);
        expect(error.isPreBroadcast, isTrue);
      }
    });

    test('fresh-quote errors carry no executed route', () {
      final noRoute =
          errored('NoRouteFound', 'No route found', {
                'reasons': _noRouteReasons,
                'provider_request_id': 'req-1',
              }, withRoute: false).error
              as rpc.RoutedSwapNoRouteTaskError;
      expect(noRoute.reasons, _noRouteReasons);
      expect(noRoute.providerRequestId, 'req-1');

      final limited =
          errored(
                'RateLimited',
                'Routed swap provider rate limit exceeded',
                <String, dynamic>{},
                withRoute: false,
              ).error
              as rpc.RoutedSwapRateLimitedTaskError;
      expect(limited.providerRequestId, isNull);

      final provider =
          errored(
                'ProviderApiError',
                'Routed swap provider returned a route for a different chain',
                {
                  'message':
                      'Routed swap provider returned a route for a different '
                      'chain',
                },
                withRoute: false,
              ).error
              as rpc.RoutedSwapProviderTaskError;
      expect(provider.message, contains('different chain'));

      final bounds =
          errored(
                'AmountOutOfBounds',
                'Parameter amount out of bounds, value: 0.0000001, min: '
                    '0.000001 max: 1000',
                {
                  'param': 'amount',
                  'value': '0.0000001',
                  'min': '0.000001',
                  'max': '1000',
                },
                withRoute: false,
              ).error
              as rpc.RoutedSwapAmountOutOfBoundsTaskError;
      expect([bounds.min, bounds.max], ['0.000001', '1000']);

      final transport =
          errored('TransportError', 'Unable to reach routed swap provider', {
                'message': 'Unable to reach routed swap provider',
              }, withRoute: false).error
              as rpc.RoutedSwapTransportTaskError;
      expect(transport.isPreBroadcast, isTrue);
    });

    test('InternalError after the handoff is not provably pre-broadcast', () {
      final error =
          errored(
                'InternalError',
                'Broadcast handoff did not return a transaction hash',
                {
                  'message':
                      'Broadcast handoff did not return a transaction hash',
                },
              ).error
              as rpc.RoutedSwapInternalTaskError;
      expect(error.message, contains('handoff'));
      expect(error.isPreBroadcast, isFalse);
    });

    test('an unknown error_type degrades and keeps its payload', () {
      final error =
          errored('SomeFutureVariant', 'Something new', {
                'detail': 'x',
                'provider_request_id': 'req-9',
              }).error
              as rpc.RoutedSwapUnknownTaskError;
      expect(error.data['detail'], 'x');
      expect(error.providerRequestId, 'req-9');
      expect(error.isPreBroadcast, isFalse);
    });
  });

  group('task::routed_swap::status and cancel refusals', () {
    Object thrownBy(void Function() parse) {
      try {
        parse();
      } on Object catch (e) {
        return e;
      }
      fail('parsed as a response');
    }

    test('status NoSuchTask reports the bare task id', () {
      final error = thrownBy(
        () => rpc.RoutedSwapStatusRequest(
          rpcPass: '',
          taskId: 3,
        ).parseResponseJson(_rpcError('NoSuchTask', "No such task '3'", 3)),
      );
      expect(error, isA<rpc.RoutedSwapNoSuchTaskException>());
      expect((error as rpc.RoutedSwapNoSuchTaskException).taskId, 3);
    });

    test('cancel answers the bare string "success"', () {
      final response = rpc.RoutedSwapCancelRequest(
        rpcPass: '',
        taskId: 3,
      ).parseResponseJson({'mmrpc': '2.0', 'result': 'success', 'id': null});
      expect(response.result, 'success');
    });

    test('cancel refusals carry {task_id}', () {
      rpc.RoutedSwapRpcException refusal(String type, String message) =>
          thrownBy(
                () => rpc.RoutedSwapCancelRequest(
                  rpcPass: '',
                  taskId: 3,
                ).parseResponseJson(_rpcError(type, message, {'task_id': 3})),
              )
              as rpc.RoutedSwapRpcException;

      final gone =
          refusal('NoSuchTask', 'No such routed swap task: 3')
              as rpc.RoutedSwapNoSuchTaskException;
      expect(gone.taskId, 3);
      final finished =
          refusal('TaskFinished', 'Routed swap task is already finished: 3')
              as rpc.RoutedSwapTaskFinishedException;
      expect(finished.taskId, 3);
      final broadcast =
          refusal(
                'TaskAlreadyBroadcast',
                'Routed swap task has already broadcast: 3',
              )
              as rpc.RoutedSwapTaskAlreadyBroadcastException;
      expect(broadcast.taskId, 3);
    });

    test('cancel InternalError carries the bare message', () {
      final error = thrownBy(
        () => rpc.RoutedSwapCancelRequest(rpcPass: '', taskId: 3)
            .parseResponseJson(
              _rpcError(
                'InternalError',
                'Unable to persist routed swap state',
                'Unable to persist routed swap state',
              ),
            ),
      );
      expect(
        (error as rpc.RoutedSwapInternalException).detail,
        'Unable to persist routed swap state',
      );
    });
  });

  group('routed_swap::history', () {
    rpc.RoutedSwapHistoryResponse page() =>
        rpc.RoutedSwapHistoryRequest(rpcPass: '').parseResponseJson(
          _envelope({
            'entries': [
              _trackingEntry,
              _cancelledEntry,
              _abortedEntry,
              _zeroResetEntry,
            ],
            'total': 14,
            'limit': 4,
            'page_number': 1,
            'total_pages': 4,
          }),
        );

    test('the envelope pages', () {
      final response = page();
      expect(response.entries, hasLength(4));
      expect([response.total, response.limit, response.pageNumber], [14, 4, 1]);
      expect(response.totalPages, 4);
      expect(response.hasMore, isTrue);
    });

    test('an in-flight entry is the live status shape', () {
      final entry = page().entries[0];
      expect(entry.isInFlight, isTrue);
      expect(entry.finishedAt, isNull);
      expect(entry.createdAt, 20);
      expect(entry.updatedAt, 24);
      expect(entry.requested.from, 'ETH');
      expect(entry.requested.amount, '1');
      expect(entry.minToAmountAccepted, '1.9');
      expect(entry.gasSpent.single.txHash, _sourceHash);
      expect(entry.totalGasSpent.single.amount, '0.000021');
      final swap = entry.swap as rpc.RoutedSwapInProgress;
      expect(swap.stage, rpc.RoutedSwapBridgeStage.destinationPending);
    });

    test('TaskCancelled is synthetic: no error_data', () {
      final entry = page().entries[1];
      expect(entry.finishedAt, 30);
      expect(entry.approvalTxHashes, [_approveHash]);
      final swap = entry.swap as rpc.RoutedSwapErrored;
      expect(swap.errorType, 'TaskCancelled');
      expect(swap.message, 'Routed swap cancelled before broadcast');
      expect(swap.error, isA<rpc.RoutedSwapTaskCancelledError>());
      expect(swap.executedRoute, isNotNull);
    });

    test('AbortedOnRestart before a route was fetched has none', () {
      final swap = page().entries[2].swap as rpc.RoutedSwapErrored;
      expect(swap.error, isA<rpc.RoutedSwapAbortedOnRestartError>());
      expect(swap.message, 'Swap aborted by node restart before broadcast');
      expect(swap.executedRoute, isNull);
    });

    test('a zero-reset keeps both approvals and every fee', () {
      // routed_swap_task_zero_reset_orders_approval_transactions.
      final entry = page().entries[3];
      expect(entry.approvalTxHashes, [_approveHash, _exactApproveHash]);
      expect(entry.gasSpent.map((g) => g.amount), [
        '0.000021',
        '0.000021',
        '0.000021',
      ]);
      expect(entry.totalGasSpent.single.amount, '0.000063');
      expect((entry.swap as rpc.RoutedSwapFinished).outcome.isSuccess, isTrue);
    });
  });
}
