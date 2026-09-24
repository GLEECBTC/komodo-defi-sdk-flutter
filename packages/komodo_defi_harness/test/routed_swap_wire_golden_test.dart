import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;

/// Parses hand-written engine JSON with the real SDK models.
///
/// Every payload below is written from the engine itself —
/// `komodo-defi-framework` `feat/lifi-integration` @ 4872ef2e,
/// `mm2src/mm2_main/src/routed_swap/{types,errors,swap_task,history}.rs` and
/// `rpc/lp_commands/routed_swap/` — with values lifted from its Rust unit
/// tests where they exist (`quote_fixture`, `completed_status`,
/// `routed_swap_task_error_wire_omits_absent_optional_fields`, …). Unlike the
/// round-trip suite this does not go through the fake, so it anchors the SDK
/// to the engine even if the fake drifts with it.
void main() {
  group('routed_swap::quote', () {
    test('an ERC-20 route with approval, totals and a symbol fee', () {
      final response =
          rpc.RoutedSwapQuoteRequest(
            rpcPass: '',
            from: 'USDT-ETH',
            to: 'USDC-POLYGON',
            amount: '1',
          ).parseResponseJson(
            _envelope({
              'routes': [_erc20Route],
            }),
          );
      final route = response.best!;

      expect(response.routes, hasLength(1));
      expect(route.provider, 'lifi');
      expect(route.from.coin, 'USDT-ETH');
      expect(route.from.amount, '1');
      expect(route.to.amount, '2');
      expect(route.toMinimum.amount, '1.9');
      expect(route.toMinimum.coin, 'USDC-POLYGON');
      expect(route.tool.key, 'across');
      expect(route.tool.name, 'Across V4');
      expect(route.tool.logoUrl, isNull);
      expect(route.kind, rpc.RoutedSwapRouteKind.crossChain);
      expect(route.fromAddress, _wallet);
      expect(route.toAddress, _wallet);
      expect(route.executionDurationS, 31);

      final approval = route.approval!;
      expect(approval.required, isTrue);
      expect(approval.txCount, 1);
      expect(approval.reason, rpc.RoutedSwapApprovalReason.noAllowance);
      expect(approval.resetsFirst, isFalse);
      expect(approval.spender, _diamond);
      expect(approval.gasCosts.single.amount.coin, 'ETH');
      expect(approval.gasCosts.single.amount.amount, '0.000057501');
      expect(approval.gasCosts.single.amountUsd, isNull);

      // ETH pays approval gas, which has no USD, so its total has none.
      expect(route.totalGasCosts.map((g) => g.amount.label), ['ETH', 'MATIC']);
      expect(route.totalGasCosts[0].amount.amount, '0.013057501');
      expect(route.totalGasCosts[0].amountUsd, isNull);
      expect(route.totalGasCosts[1].amountUsd, '4');

      expect(route.steps.map((s) => s.stepType), [
        rpc.RoutedSwapStepType.swap,
        rpc.RoutedSwapStepType.cross,
      ]);
      expect(route.steps[0].chainId, 1);
      expect(route.steps[1].fromChainId, 1);
      expect(route.steps[1].toChainId, 137);

      expect(route.feeCosts.map((f) => f.included), [true, false, true]);
      expect(route.feeCosts[1].amount.coin, 'FEE-INACTIVE');
      expect(route.feeCosts[2].amount.symbol, 'BROKEN');
      expect(route.feeCosts[2].amount.coin, isNull);
      expect(route.feeCosts[2].amount.isKnownAsset, isFalse);
      expect(route.gasCosts.map((g) => g.amountUsd), ['20', '4', '6']);

      // The model reproduces the wire exactly, for exports and support.
      expect(route.toJson(), _erc20Route);
    });

    test('a native route has no approval and totals with USD', () {
      final route = rpc.RoutedSwapRoute.fromJson(_nativeRoute);
      expect(route.approval, isNull);
      expect(route.tool.logoUrl, 'https://cdn.example/logo.svg');
      expect(route.totalGasCosts.map((g) => g.amountUsd), ['26', '4']);
      expect(route.toJson(), _nativeRoute);
    });

    test('a zero-reset approval is two transactions', () {
      final route = rpc.RoutedSwapRoute.fromJson({
        ..._erc20Route,
        'approval': const {
          'required': true,
          'tx_count': 2,
          'reason': 'zero_reset',
          'spender': _diamond,
          'gas_costs': [
            {'coin': 'ETH', 'amount': '0.000115002'},
          ],
        },
      });
      expect(route.approval!.txCount, 2);
      expect(route.approval!.reason, rpc.RoutedSwapApprovalReason.zeroReset);
      expect(route.approval!.resetsFirst, isTrue);
    });

    test('every quote error arrives as its typed exception', () {
      rpc.RoutedSwapRpcException thrown(Map<String, dynamic> error) {
        try {
          rpc.RoutedSwapQuoteRequest(
            rpcPass: '',
            from: 'ETH',
            to: 'USDC-POLYGON',
            amount: '1',
          ).parseResponseJson(error);
        } on rpc.RoutedSwapRpcException catch (e) {
          return e;
        }
        fail('${error['error_type']} parsed as a response');
      }

      final coin =
          thrown(
                _rpcError('CoinNotActive', 'Coin FEE-INACTIVE is not active', {
                  'coin': 'FEE-INACTIVE',
                }),
              )
              as rpc.RoutedSwapCoinNotActiveException;
      expect(coin.coin, 'FEE-INACTIVE');
      expect(coin.message, 'Coin FEE-INACTIVE is not active');

      final pair =
          thrown(
                _rpcError(
                  'PairNotSupported',
                  'Pair ETH/BTC is not supported: BTC is not an EVM asset',
                  {
                    'from': 'ETH',
                    'to': 'BTC',
                    'reason': 'BTC is not an EVM asset',
                  },
                ),
              )
              as rpc.RoutedSwapPairNotSupportedException;
      expect([pair.from, pair.to], ['ETH', 'BTC']);

      final param =
          thrown(
                _rpcError(
                  'InvalidParam',
                  'Invalid parameter amount: more than 6 decimal places',
                  {'param': 'amount', 'reason': 'more than 6 decimal places'},
                ),
              )
              as rpc.RoutedSwapInvalidParamException;
      expect(param.param, 'amount');

      final bounds =
          thrown(
                _rpcError(
                  'AmountOutOfBounds',
                  'Parameter slippage out of bounds, value: 0.6, min: 0 max: '
                      '0.5',
                  {
                    'param': 'slippage',
                    'value': '0.6',
                    'min': '0',
                    'max': '0.5',
                  },
                ),
              )
              as rpc.RoutedSwapAmountOutOfBoundsException;
      expect(
        [bounds.param, bounds.value, bounds.min, bounds.max],
        ['slippage', '0.6', '0', '0.5'],
      );

      final address =
          thrown(
                _rpcError(
                  'MyAddressError',
                  'Cannot use ETH source address: no enabled address',
                  {'coin': 'ETH', 'message': 'no enabled address'},
                ),
              )
              as rpc.RoutedSwapMyAddressException;
      expect(address.detail, 'no enabled address');

      final config =
          thrown(
                _rpcError('InvalidConfig', 'lifi_api is invalid', {
                  'message': 'lifi_api is invalid',
                }),
              )
              as rpc.RoutedSwapInvalidConfigException;
      expect(config.detail, 'lifi_api is invalid');

      final noRoute =
          thrown(
                _rpcError('NoRouteFound', 'No route found', {
                  'reasons': _noRouteReasons,
                  'provider_request_id': 'req-1',
                }),
              )
              as rpc.RoutedSwapNoRouteException;
      expect(noRoute.reasons, _noRouteReasons);
      expect(noRoute.providerRequestId, 'req-1');

      final limited =
          thrown(
                _rpcError(
                  'RateLimited',
                  'Routed swap provider rate limit exceeded',
                  <String, dynamic>{},
                ),
              )
              as rpc.RoutedSwapRateLimitedException;
      expect(limited.providerRequestId, isNull);
      expect(limited.isTransient, isTrue);

      final provider =
          thrown(
                _rpcError(
                  'ProviderApiError',
                  'Routed swap provider returned an invalid transaction target',
                  {
                    'message':
                        'Routed swap provider returned an invalid transaction '
                        'target',
                    'provider_request_id': 'req-2',
                  },
                ),
              )
              as rpc.RoutedSwapProviderException;
      expect(provider.providerRequestId, 'req-2');
      expect(provider.detail, startsWith('Routed swap provider returned'));

      final transport =
          thrown(
                _rpcError(
                  'TransportError',
                  'Unable to reach routed swap provider',
                  {'message': 'Unable to reach routed swap provider'},
                ),
              )
              as rpc.RoutedSwapTransportException;
      expect(transport.detail, 'Unable to reach routed swap provider');

      final internal =
          thrown(
                _rpcError(
                  'InternalError',
                  'Unable to access routed swap '
                      'history',
                  {
                    'message':
                        'Unable to access routed swap '
                        'history',
                  },
                ),
              )
              as rpc.RoutedSwapInternalException;
      expect(internal.detail, 'Unable to access routed swap history');

      // A dispatcher rejection before the handler runs.
      final request = thrown(
        _rpcError(
          'InvalidRequest',
          'Error parsing request: unknown field `client_id`',
          'unknown field `client_id`',
        ),
      );
      expect(request, isA<rpc.RoutedSwapUnknownRpcException>());
      expect(request.errorType, 'InvalidRequest');
    });
  });

  test('routed_swap::supported_coins', () {
    final response = rpc.RoutedSwapSupportedCoinsRequest(rpcPass: '')
        .parseResponseJson(
          _envelope({
            'provider': 'lifi',
            'coins': [
              {'coin': 'ETH', 'chain_id': 1},
              {'coin': 'USDC-POLYGON', 'chain_id': 137},
            ],
          }),
        );
    expect(response.provider, 'lifi');
    expect(response.coins.map((c) => [c.coin, c.chainId]), [
      ['ETH', 1],
      ['USDC-POLYGON', 137],
    ]);
  });

  test('task::routed_swap::init answers the task id only', () {
    final response = rpc.RoutedSwapInitRequest(
      rpcPass: '',
      from: 'ETH',
      to: 'USDC-POLYGON',
      amount: '1',
      minToAmount: '1.9',
    ).parseResponseJson(_envelope({'task_id': 3}));
    expect(response.taskId, 3);
  });

  group('task::routed_swap::status in progress', () {
    rpc.RoutedSwapInProgress inProgress(Map<String, dynamic> details) =>
        _status('InProgress', details) as rpc.RoutedSwapInProgress;

    test('FetchingQuote carries no executed route yet', () {
      final status = inProgress({
        'state': 'FetchingQuote',
        'uuid': _uuid,
        'provider': 'lifi',
      });
      expect(status.state, rpc.RoutedSwapState.fetchingQuote);
      expect(status.uuid, _uuid);
      expect(status.provider, 'lifi');
      expect(status.executedRoute, isNull);
      expect(status.state.isCancellable, isTrue);
    });

    test('every later state carries the executed route', () {
      for (final state in [
        'CheckingAllowance',
        'Approving',
        'Signing',
        'Broadcasting',
      ]) {
        final status = inProgress({
          'state': state,
          'uuid': _uuid,
          'provider': 'lifi',
          'executed_route': _nativeRoute,
        });
        expect(status.rawState, state);
        expect(status.state, isNot(rpc.RoutedSwapState.unknown));
        expect(
          status.executedRoute,
          rpc.RoutedSwapRoute.fromJson(_nativeRoute),
        );
        expect(status.sourceTxHash, isNull);
      }
    });

    test('Approving gains the approval hash once broadcast', () {
      final status = inProgress({
        'state': 'Approving',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _erc20Route,
        'approve_tx_hash': _approveHash,
      });
      expect(status.approveTxHash, _approveHash);
      expect(status.state.isCancellable, isTrue);
    });

    test('Broadcasting and confirmation carry the source hash', () {
      final broadcasting = inProgress({
        'state': 'Broadcasting',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _nativeRoute,
        'source_tx_hash': _sourceHash,
      });
      expect(broadcasting.sourceTxHash, _sourceHash);
      expect(broadcasting.state.isCancellable, isFalse);

      final waiting = inProgress({
        'state': 'WaitingSourceConfirmation',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _nativeRoute,
        'source_tx_hash': _sourceHash,
      });
      expect(waiting.state, rpc.RoutedSwapState.waitingSourceConfirmation);
      expect(waiting.sourceTxHash, _sourceHash);
    });

    test('TrackingBridge: the bare first poll, then provider detail', () {
      final first = inProgress({
        'state': 'TrackingBridge',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _nativeRoute,
        'source_tx_hash': _sourceHash,
        'stage': 'unknown',
        'execution_duration_s': 31,
      });
      expect(first.stage, rpc.RoutedSwapBridgeStage.unknown);
      expect(first.substatus, isNull);
      expect(first.providerExplorerUrl, isNull);
      expect(first.executionDurationS, 31);

      final pending = inProgress({
        'state': 'TrackingBridge',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _nativeRoute,
        'source_tx_hash': _sourceHash,
        'stage': 'destination_pending',
        'substatus': 'WAIT_DESTINATION_TRANSACTION',
        'substatus_message': 'Waiting for the destination transaction.',
        'provider_explorer_url': 'https://scan.li.fi/tx/$_sourceHash',
        'execution_duration_s': 31,
      });
      expect(pending.stage, rpc.RoutedSwapBridgeStage.destinationPending);
      expect(pending.substatus, 'WAIT_DESTINATION_TRANSACTION');
      expect(pending.substatusMessage, startsWith('Waiting'));
      expect(pending.providerExplorerUrl, endsWith(_sourceHash));

      for (final (wire, stage) in [
        ('bridging', rpc.RoutedSwapBridgeStage.bridging),
        ('refund_pending', rpc.RoutedSwapBridgeStage.refundPending),
        ('teleporting', rpc.RoutedSwapBridgeStage.unknown),
      ]) {
        final status = inProgress({
          'state': 'TrackingBridge',
          'uuid': _uuid,
          'provider': 'lifi',
          'executed_route': _nativeRoute,
          'source_tx_hash': _sourceHash,
          'stage': wire,
          'execution_duration_s': 31,
        });
        expect(status.stage, stage);
        expect(status.rawStage, wire);
      }
    });

    test('action_required carries action_url (not emitted in v1)', () {
      final status = inProgress({
        'state': 'TrackingBridge',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _nativeRoute,
        'source_tx_hash': _sourceHash,
        'stage': 'action_required',
        'action_url': 'https://li.fi/act',
        'execution_duration_s': 31,
      });
      expect(status.stage, rpc.RoutedSwapBridgeStage.actionRequired);
      expect(status.actionUrl, 'https://li.fi/act');
    });
  });

  group('task::routed_swap::status Ok', () {
    rpc.RoutedSwapFinished finished(Map<String, dynamic> details) =>
        _status('Ok', details) as rpc.RoutedSwapFinished;

    test('completed cross-chain', () {
      final status = finished({
        'outcome': 'completed',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _nativeRoute,
        'received': {'coin': 'USDC-POLYGON', 'amount': '2'},
        'source_tx_hash': _sourceHash,
        'dest_tx_hash': _destHash,
        'provider_explorer_url': 'https://scan.li.fi/tx/$_sourceHash',
      });
      expect(status.outcome, rpc.RoutedSwapOutcome.completed);
      expect(status.outcome.isSuccess, isTrue);
      expect(status.partialReason, isNull);
      expect(status.received.coin, 'USDC-POLYGON');
      expect(status.received.amount, '2');
      expect(status.sourceTxHash, _sourceHash);
      expect(status.destTxHash, _destHash);
      expect(status.executedRoute, isNotNull);
    });

    test('completed same-chain has no destination hash nor link', () {
      final status = finished({
        'outcome': 'completed',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _nativeRoute,
        'received': {'coin': 'USDT-ETH', 'amount': '2'},
        'source_tx_hash': _sourceHash,
      });
      expect(status.destTxHash, isNull);
      expect(status.providerExplorerUrl, isNull);
    });

    test('partial carries partial_reason and is not a success', () {
      final below = finished({
        'outcome': 'partial',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _nativeRoute,
        'partial_reason': 'below_minimum',
        'received': {'coin': 'USDC-POLYGON', 'amount': '1.5'},
        'source_tx_hash': _sourceHash,
        'dest_tx_hash': _destHash,
      });
      expect(below.outcome.isSuccess, isFalse);
      expect(below.partialReason, rpc.RoutedSwapPartialReason.belowMinimum);

      final intermediate = finished({
        'outcome': 'partial',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _nativeRoute,
        'partial_reason': 'intermediate_token',
        'received': {'symbol': 'axlUSDC', 'amount': '1.99'},
        'source_tx_hash': _sourceHash,
        'dest_tx_hash': _destHash,
      });
      expect(
        intermediate.partialReason,
        rpc.RoutedSwapPartialReason.intermediateToken,
      );
      expect(intermediate.received.isKnownAsset, isFalse);
      expect(intermediate.received.label, 'axlUSDC');
    });

    test('refunded returns the source coin, with no destination hash', () {
      final status = finished({
        'outcome': 'refunded',
        'uuid': _uuid,
        'provider': 'lifi',
        'executed_route': _nativeRoute,
        'received': {'coin': 'ETH', 'amount': '1'},
        'source_tx_hash': _sourceHash,
        'provider_explorer_url': 'https://scan.li.fi/tx/$_sourceHash',
      });
      expect(status.outcome, rpc.RoutedSwapOutcome.refunded);
      expect(status.outcome.isSuccess, isFalse);
      expect(status.received.coin, 'ETH');
      expect(status.destTxHash, isNull);
    });
  });

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

const String _uuid = '0d4dbd0c-5a4e-4b7f-9c1d-2e3f4a5b6c7d';
const String _wallet = '0x9f3aE7e1b2C4d5E6f7A8b9C0d1E2f3A4b5C6d7E8';
const String _diamond = '0x5555555555555555555555555555555555555555';
const String _sourceHash =
    '0x1111111111111111111111111111111111111111111111111111111111111111';
const String _destHash =
    '0x0000000000000000000000000000000000000000000000000000000000000002';
const String _approveHash =
    '0xa1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1';
const String _exactApproveHash =
    '0xa2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2';

/// `no_route_reasons` in errors.rs: provider summary, failed tools, then
/// filtered-out candidates.
const List<String> _noRouteReasons = [
  'no liquidity',
  'amount too low (hop)',
  'slippage exceeded (across)',
  'amount out of range',
];

/// `quote_fixture` / `source_token_fixture` through `build_route`, as
/// asserted by `erc20_quote_includes_direct_approval_cost_and_totals`.
final Map<String, dynamic> _erc20Route = _decode('''
{
  "provider": "lifi",
  "from": {"coin": "USDT-ETH", "amount": "1"},
  "to": {"coin": "USDC-POLYGON", "amount": "2", "amount_min": "1.9"},
  "tool": {"key": "across", "name": "Across V4"},
  "kind": "cross_chain",
  "from_address": "$_wallet",
  "to_address": "$_wallet",
  "approval": {
    "required": true,
    "tx_count": 1,
    "reason": "no_allowance",
    "spender": "$_diamond",
    "gas_costs": [{"coin": "ETH", "amount": "0.000057501"}]
  },
  "total_gas_costs": [
    {"coin": "ETH", "amount": "0.013057501"},
    {"coin": "MATIC", "amount": "0.002", "amount_usd": "4"}
  ],
  "steps": [
    {"type": "swap", "tool": "1inch", "chain_id": 1},
    {
      "type": "cross",
      "tool": "across",
      "from_chain_id": 1,
      "to_chain_id": 137
    }
  ],
  "fee_costs": [
    {
      "name": "native fee",
      "coin": "MATIC",
      "amount": "0.001",
      "included": true
    },
    {
      "name": "configured inactive fee",
      "coin": "FEE-INACTIVE",
      "amount": "0.25",
      "included": false
    },
    {
      "name": "malformed address fee",
      "symbol": "BROKEN",
      "amount": "0.25",
      "included": true
    }
  ],
  "gas_costs": [
    {"coin": "ETH", "amount": "0.01", "amount_usd": "20"},
    {"coin": "MATIC", "amount": "0.002", "amount_usd": "4"},
    {"coin": "ETH", "amount": "0.003", "amount_usd": "6"}
  ],
  "execution_duration_s": 31
}
''');

/// `native_cross_chain_quote_ignores_approval_metadata`: no approval, so
/// both totals keep USD (ETH 20 + 6).
final Map<String, dynamic> _nativeRoute = {
  ..._erc20Route,
  'from': {'coin': 'ETH', 'amount': '1'},
  'tool': {
    'key': 'across',
    'name': 'Across V4',
    'logo_url': 'https://cdn.example/logo.svg',
  },
  'total_gas_costs': [
    {'coin': 'ETH', 'amount': '0.013', 'amount_usd': '26'},
    {'coin': 'MATIC', 'amount': '0.002', 'amount_usd': '4'},
  ],
}..remove('approval');

final Map<String, dynamic> _trackingEntry = _decode('''
{
  "created_at": 20,
  "updated_at": 24,
  "requested": {"from": "ETH", "to": "USDC-POLYGON", "amount": "1"},
  "min_to_amount_accepted": "1.9",
  "approval_tx_hashes": [],
  "gas_spent": [
    {"tx_hash": "$_sourceHash", "coin": "ETH", "amount": "0.000021"}
  ],
  "total_gas_spent": [{"coin": "ETH", "amount": "0.000021"}],
  "swap": {
    "status": "InProgress",
    "details": {
      "state": "TrackingBridge",
      "uuid": "$_uuid",
      "provider": "lifi",
      "executed_route": ${jsonEncode(_nativeRoute)},
      "source_tx_hash": "$_sourceHash",
      "stage": "destination_pending",
      "substatus": "WAIT_DESTINATION_TRANSACTION",
      "execution_duration_s": 31
    }
  }
}
''');

final Map<String, dynamic> _cancelledEntry = _decode('''
{
  "created_at": 20,
  "updated_at": 30,
  "finished_at": 30,
  "requested": {"from": "USDT-ETH", "to": "USDC-POLYGON", "amount": "1"},
  "min_to_amount_accepted": "1.9",
  "approval_tx_hashes": ["$_approveHash"],
  "gas_spent": [
    {"tx_hash": "$_approveHash", "coin": "ETH", "amount": "0.002"}
  ],
  "total_gas_spent": [{"coin": "ETH", "amount": "0.002"}],
  "swap": {
    "status": "Error",
    "details": {
      "uuid": "00000000-0000-0000-0000-000000000003",
      "provider": "lifi",
      "executed_route": ${jsonEncode(_erc20Route)},
      "error_type": "TaskCancelled",
      "error": "Routed swap cancelled before broadcast"
    }
  }
}
''');

final Map<String, dynamic> _abortedEntry = _decode('''
{
  "created_at": 10,
  "updated_at": 15,
  "finished_at": 15,
  "requested": {"from": "ETH", "to": "USDC-POLYGON", "amount": "1"},
  "min_to_amount_accepted": "1.9",
  "approval_tx_hashes": [],
  "gas_spent": [],
  "total_gas_spent": [],
  "swap": {
    "status": "Error",
    "details": {
      "uuid": "00000000-0000-0000-0000-000000000001",
      "provider": "lifi",
      "error_type": "AbortedOnRestart",
      "error": "Swap aborted by node restart before broadcast"
    }
  }
}
''');

final Map<String, dynamic> _zeroResetEntry = _decode('''
{
  "created_at": 5,
  "updated_at": 9,
  "finished_at": 9,
  "requested": {"from": "USDT-ETH", "to": "USDT-ETH", "amount": "1"},
  "min_to_amount_accepted": "1.9",
  "approval_tx_hashes": ["$_approveHash", "$_exactApproveHash"],
  "gas_spent": [
    {"tx_hash": "$_approveHash", "coin": "ETH", "amount": "0.000021"},
    {"tx_hash": "$_exactApproveHash", "coin": "ETH", "amount": "0.000021"},
    {"tx_hash": "$_sourceHash", "coin": "ETH", "amount": "0.000021"}
  ],
  "total_gas_spent": [{"coin": "ETH", "amount": "0.000063"}],
  "swap": {
    "status": "Ok",
    "details": {
      "outcome": "completed",
      "uuid": "00000000-0000-0000-0000-000000000004",
      "provider": "lifi",
      "executed_route": ${jsonEncode(_erc20Route)},
      "received": {"coin": "USDT-ETH", "amount": "2"},
      "source_tx_hash": "$_sourceHash"
    }
  }
}
''');

Map<String, dynamic> _decode(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

Map<String, dynamic> _envelope(Object result) => {
  'mmrpc': '2.0',
  'result': result,
  'id': null,
};

/// A top-level MMRPC error: `MmRpcResponse` with the serialized `MmError`
/// flattened beside `mmrpc`.
Map<String, dynamic> _rpcError(String type, String message, Object data) => {
  'mmrpc': '2.0',
  'error': message,
  'error_path': 'routed_swap',
  'error_trace': 'routed_swap:1]',
  'error_type': type,
  'error_data': data,
  'id': null,
};

/// Parses a `task::routed_swap::status` response through the request, so a
/// terminal `Error` must come back as a response rather than be thrown.
rpc.RoutedSwapStatus _status(String status, Map<String, dynamic> details) {
  final json =
      jsonDecode(jsonEncode(_envelope({'status': status, 'details': details})))
          as Map<String, dynamic>;
  final response = rpc.RoutedSwapStatusRequest(
    rpcPass: '',
    taskId: 3,
  ).parseResponseJson(json);
  expect(response.status, status);
  return response.details;
}
